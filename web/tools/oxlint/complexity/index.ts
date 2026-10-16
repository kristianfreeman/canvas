import { defineRule, eslintCompatPlugin } from "@oxlint/plugins";

import type { ESTree } from "@oxlint/plugins";

type Node = ESTree.Node;

type FunctionNode =
  | ESTree.FunctionDeclaration
  | ESTree.FunctionExpression
  | ESTree.ArrowFunctionExpression;

const NESTING = new Set([
  "IfStatement",
  "ConditionalExpression",
  "SwitchStatement",
  "ForStatement",
  "ForInStatement",
  "ForOfStatement",
  "WhileStatement",
  "DoWhileStatement",
  "CatchClause",
]);

const FUNCTIONS = new Set(["FunctionDeclaration", "FunctionExpression", "ArrowFunctionExpression"]);

const LOGICAL = new Set(["&&", "||", "??"]);

function isNode(value: Node | Node[] | string | number | boolean | null | undefined): value is Node {
  return value !== null && !Array.isArray(value) && value instanceof Object && "type" in value;
}

function children(node: Node): Node[] {
  const out: Node[] = [];

  for (const [key, value] of Object.entries(node)) {
    if (key === "parent") continue;
    if (Array.isArray(value)) {
      for (const item of value) if (isNode(item)) out.push(item);
    } else if (isNode(value)) {
      out.push(value);
    }
  }

  return out;
}

/**
 * Cognitive complexity after SonarSource's definition: +1 for each break in
 * linear flow, plus the current nesting depth for structures that nest.
 * Nested functions are scored on their own.
 */
function score(node: Node, nesting: number, parent: Node | null): number {
  if (FUNCTIONS.has(node.type)) return 0;

  let total = 0;
  let inner = nesting;

  if (NESTING.has(node.type)) {
    const isElseIf = node.type === "IfStatement" && parent?.type === "IfStatement" && parent.alternate === node;
    total += isElseIf ? 1 : 1 + nesting;
    inner = isElseIf ? nesting : nesting + 1;
  }

  if (node.type === "IfStatement" && node.alternate && node.alternate.type !== "IfStatement") total += 1;

  if (node.type === "LogicalExpression" && LOGICAL.has(node.operator)) {
    const continues = parent?.type === "LogicalExpression" && parent.operator === node.operator;
    if (!continues) total += 1;
  }

  if ((node.type === "BreakStatement" || node.type === "ContinueStatement") && node.label) total += 1;

  for (const child of children(node)) {
    const isElseIf = node.type === "IfStatement" && child === node.alternate && child.type === "IfStatement";
    total += score(child, isElseIf ? nesting : inner, node);
  }

  return total;
}

function functionName(node: FunctionNode): string {
  if (node.id) return `'${node.id.name}'`;
  const parent = node.parent;
  if (parent?.type === "VariableDeclarator" && parent.id.type === "Identifier") return `'${parent.id.name}'`;
  if (parent?.type === "Property" && parent.key.type === "Identifier") return `'${parent.key.name}'`;
  if (parent?.type === "MethodDefinition" && parent.key.type === "Identifier") return `'${parent.key.name}'`;

  return "this function";
}

const cognitiveComplexityRule = defineRule({
  meta: {
    type: "suggestion",
    docs: { description: "Limit the cognitive complexity of each function." },
    schema: [{ type: "integer", minimum: 0 }],
    messages: {
      tooComplex: "Cognitive complexity of {{name}} is {{score}} (max {{max}}). Split it up or flatten the branching.",
    },
  },
  create(context) {
    const max = Number(context.options[0] ?? 10);

    const check = (node: FunctionNode): void => {
      const total = score(node.body, 0, node);
      if (total > max) {
        context.report({
          node,
          messageId: "tooComplex",
          data: { name: functionName(node), score: String(total), max: String(max) },
        });
      }
    };

    return {
      FunctionDeclaration: check,
      FunctionExpression: check,
      ArrowFunctionExpression: check,
    };
  },
});

export default eslintCompatPlugin({
  meta: { name: "complexity" },
  rules: { "cognitive-complexity": cognitiveComplexityRule },
});

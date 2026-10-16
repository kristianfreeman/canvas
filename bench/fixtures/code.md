# Deploy plan

Two code blocks in different languages, so the highlighter loads grammars.

```ts
export function retry<T>(fn: () => Promise<T>, attempts = 3): Promise<T> {
  return fn().catch((error) => (attempts > 1 ? retry(fn, attempts - 1) : Promise.reject(error)))
}
```

```bash
canvas show plan.md --wait --buttons "Approve,Reject" | jq -r .
```

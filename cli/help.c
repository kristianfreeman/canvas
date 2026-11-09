#include "args.h"
#include "commands.h"
#include "util.h"

static const char help_usage[] =
    "usage:\n"
    "  canvas show [FILE | -] [options]             render, return once rendered\n"
    "  canvas toggle [FILE | -] [options]           hide if --id is visible, else show\n"
    "  canvas toggle --all                          hide every shown panel, or bring back\n"
    "                                               the hidden ones (the global hotkey)\n"
    "  canvas update --id ID (--data D | --stream)  replace an open canvas's data\n"
    "  canvas move --id ID [placement options]      reposition an open canvas\n"
    "  canvas hide [--id ID | --all]\n"
    "  canvas list                                  one JSON object per visible panel\n"
    "  canvas pub CHANNEL [VALUE | -] [--merge] [--persist] [--keep N] [--every DUR -- CMD...]\n"
    "  canvas sub CHANNEL... [--history]            NDJSON on stdout until killed\n"
    "  canvas get CHANNEL                           print a channel's latest value\n"
    "  canvas hotkeys                               one JSON object per hotkey\n"
    "  canvas ping                                  exit 0 if the server is up\n"
    "  canvas help\n"
    "  --emit on any of these but sub, pub - and pub --every prints the request\n"
    "  line instead of sending it\n"
    "\n";

static const char help_content[] =
    "content options (show, toggle):\n"
    "  FILE | -               a file, watched and re-rendered when it changes; - (or a\n"
    "                         non-TTY stdin with no FILE) reads the source from stdin\n"
    "  --id ID                panel id, default `default`; an existing id is replaced\n"
    "  --kind md|markdown|tsx|jsx\n"
    "                         .tsx .jsx .ts files are TSX; stdin is sniffed\n"
    "  --title T              defaults to the file name\n"
    "  --data FILE|-|JSON     props data; JSON if it starts with { [ \" a digit or -,\n"
    "                         or is true, false or null; otherwise a file path\n"
    "  --stream               after rendering, each stdin line replaces data (needs FILE)\n"
    "  --theme auto|dark|light\n"
    "  --accent COLOR         any CSS color; defaults to the macOS accent color\n"
    "  --wait                 block until the user acts\n"
    "  --buttons \"A,B\"        footer buttons; the first is primary, the result is the label\n"
    "  --focus | --no-focus   default: on for --wait and toggle, off otherwise\n"
    "  --timeout SECONDS      with --wait: hide the panel and exit 3 when it runs out\n"
    "  --trace                print stage timings to stderr as one JSON line\n"
    "  --hotkey KEYS          a global hotkey like ctrl+opt+t that hides and shows this\n"
    "                         id, and shows it again once closed; none removes it\n"
    "  --emit                 print the request line instead of sending it; replay it\n"
    "                         with canvas-send from cli/canvas-send.zsh, which needs no exec\n"
    "\n"
    "placement options (show, toggle, move), in points:\n"
    "  --position P           center (default), top, bottom, left, right, top-left,\n"
    "                         top-right, bottom-left, bottom-right, mouse\n"
    "  --at X,Y               from the visible frame's top-left; negative X or Y measures\n"
    "                         from the right or bottom; N% works; overrides --position\n"
    "  --screen S             mouse (default), main, focused, N (1-based) or NAME\n"
    "  --margin N             gap to the screen edges for presets, default 24\n"
    "  --width N|N%           default 720\n"
    "  --height N|N%          fixed height; without it the height follows the content\n"
    "  --min-height N|N%, --max-height N|N%\n"
    "                         bounds on the content height; --max-height defaults to 85%\n"
    "  --resizable | --no-resizable\n"
    "  --level normal|floating|top\n"
    "  --spaces all|current\n"
    "  --pin                  floating on all Spaces; Esc doesn't close it\n"
    "  --click-through        the panel ignores the mouse (use with --pin)\n"
    "  --opacity F            0.0 to 1.0, default 1\n"
    "  --stack GROUP          stack panels of a group in their corner\n"
    "  --forget               ignore and clear this id's remembered frame\n"
    "\n";

static const char help_channels[] =
    "channels:\n"
    "  pub CHANNEL VALUE      publish one JSON value (same JSON-or-file rule as --data)\n"
    "  pub CHANNEL -          each stdin line is one message; exits 0 on EOF\n"
    "  pub CHANNEL --every DUR -- CMD ARGS...\n"
    "                         run CMD every DUR (500ms, 1s, 2.5m) and publish its stdout\n"
    "  --merge                apply VALUE as a JSON merge patch (RFC 7386)\n"
    "  --keep N               history capacity, default 120, 0 turns it off\n"
    "  --persist              keep the channel's latest value across server restarts\n"
    "  pub CHANNEL --clear    delete the channel's value, history and persistence\n"
    "  sub CHANNEL...         one line per message: the bare value for one channel,\n"
    "                         {\"channel\",\"value\"} for several\n"
    "  --history              print the buffered history first\n"
    "  names are dot-separated [a-z0-9_-] segments; canvas.* is reserved\n"
    "\n"
    "exit codes: 0 ok, 1 error, 2 closed or replaced, 3 timed out, 64 usage\n";

void help_write(int fd) {
    (void)write_all(fd, help_usage, sizeof help_usage - 1);
    (void)write_all(fd, help_content, sizeof help_content - 1);
    (void)write_all(fd, help_channels, sizeof help_channels - 1);
}

int cmd_help(Args *a) {
    (void)a;
    help_write(1);
    return 0;
}

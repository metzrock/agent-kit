# Set up agent-kit

1. Detect the OS. On Windows without WSL, guide the user through `install.ps1`.
2. Clone `https://github.com/OWNER/agent-kit`, then run `bin/agent-kit list --json`.
3. Ask which modules the user wants. Give one plain line per module. Ask which model
   they want for everyday work.
4. Run `bin/agent-kit install --modules … --model … --yes` with their choices.
5. Run `bin/agent-kit doctor` and summarize the result.
6. Offer `bin/agent-kit interview`.

Rules:
- Show each command before running it.
- Never read or print credential files or tokens.
- Touch only what the installer touches.

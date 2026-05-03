# smoovmux instructions

Canonical agent instructions now live in [`AGENTS.md`](./AGENTS.md).

Read and follow `AGENTS.md` before making changes. In particular, the TDD rules there are mandatory:

- write or update a focused test before production code,
- run it and confirm the expected failure,
- then implement the smallest production change,
- if no practical test seam exists, stop and explain before editing production code.

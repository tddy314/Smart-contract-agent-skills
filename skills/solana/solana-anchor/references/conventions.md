# Solana / Anchor Conventions (House Style)

These conventions come from the team's production Solana work. Apply them to code, comments, READMEs, commit messages, and chat. They exist to keep the codebase truthful, minimal, and consistent with current (2026) Solana practice.

## Table of Contents

- Terminology
- Truthfulness
- Naming
- Code quality
- Configuration files
- Documentation
- Writing about financial software
- Tooling and versions
- Dead / deprecated tools to avoid

---

## Terminology

Solana is not Ethereum. Ethereum concepts do not belong in Solana docs.

- Use "programs", not "smart contracts".
- Use "transaction fees", not "gas".
- There are no mempools.
- "Instruction handlers" = the Rust functions; "instructions" = the data passed to them. Solana overloads the word "instruction" for both; disambiguate.
- Token program names:
  - "Token Extensions Program" or "Token extensions" for the newer program (not "Token 2022", which is a code name).
  - "Classic Token Program" for the older one.
  - Plain "Token" rather than "SPL Token" unless contrasting SOL (the native token) with all other tokens.
- "onchain" and "offchain" are single, unhyphenated words. Never "on-chain" / "off-chain". Same for "crosschain".
- A mint is the onchain account controlling supply; a token is the asset. In economic prose use "token A"/"token B"; reserve "mint account" for the technical argument passed to an instruction.

## Truthfulness

Do not write things that are not currently true - in code, comments, variable names, READMEs, or commit messages.

- Comments and docs that do not match the code are untrue. Fix them when you see them.
- Variable names that do not match their purpose are untrue.
- Mark temporary workarounds with a `TODO` that says what the real fix is and when the workaround can go.
- Disambiguate pronouns and overloaded terms; ambiguity that reads as true one way and false the other is a soft lie.
- Describe what *is*, not what was removed. "No longer uses X", "previously", "replaces the old Y" belong in commit messages, not source. A first-time reader has no history.
- **Grep before naming.** Before writing prose that names a function, struct, account, field, or constant, grep the source to confirm the identifier exists with that exact name.

## Naming

- Arrays are plural (`reserves`); the loop item is singular (`reserves.iter().for_each(|reserve| ...)`).
- Functions are verby: `calculate_borrow_rate`, `get_exchange_rate`.
- Avoid abbreviations; prefer full words. Avoid single-letter names outside math. Do not use `ctx` if `context` reads clearly in the surrounding code - match the repo, but bias to clarity.
- Name a transaction `transaction`, an instruction `instruction`, a signature `signature`. Do not call an instruction a "transaction".
- Give numbers names. `FULL_BPS = 10_000`, `SLOTS_PER_YEAR = 63_072_000`. If a value comes from an IDL, import the IDL and read it rather than copying the literal.

## Code quality

- You are a deletionist: perfection is when there is nothing left to remove. Delete dead code, unused imports/constants, commented-out handlers, and comments that merely restate the code.
- A doc comment whose first line paraphrases the identifier is noise. Either say something the name cannot (seed derivation, an invariant, a rounding rationale) or delete it.
- No placeholder logic, no "in production we'd do this differently", no functions returning fake data. Ship the real thing.
- `Box` large accounts to avoid stack overflow. Use zero-copy (`AccountLoader`) for big or array-heavy state.

## Configuration files

When you change or pin a value in `Anchor.toml`, `Cargo.toml`, `package.json`, `rust-toolchain.toml`, or CI, leave a comment explaining *why* - what breaks without it, when it can be unpinned.

```toml
# Pinned: 0.8.7 conflicts with litesvm's dep tree.
# Unpin when litesvm upgrades its ahash requirement.
ahash = "=0.8.6"
```

Pin dependency versions. Avoid open ranges like `solana-program = ">=1.16, <1.18"` on a production program. Pin git CPI deps to a commit or tag, not a branch, so builds are reproducible. When you remove a config section, put the rationale in the commit, not the file.

## Documentation

Every program needs a `README.md` covering Purpose, Major Concepts (key PDAs, state, program logic), Testing (how to run), Setup, and Usage. Keep it specific to the program, not boilerplate.

- No numbered headings (they break when sections move).
- No preview paragraphs ("the sections below cover...") - the headings already say that.
- Inline each handler's mechanics into the lifecycle prose at the point it is first called, rather than a separate flat instruction reference.
- Bold canonical terms on first use, plain after.
- No ASCII art, no Mermaid, no markdown tables - they do not render well on chat surfaces. Use headings, nested bullets, or prose.
- No em-dashes (an LLM-output tell). Use a regular dash or rewrite.

## Writing about financial software

For AMMs, escrows, lending, vaults, leasing, CLOBs, stablecoins:

- "Non-custodial" is loaded. If the program locks funds in vaults (every escrow/lending/vault program does), do not claim non-custodial - describe the custody arrangement instead (program-owned vault, PDA signer, no admin escape hatch).
- Upgrade authority is normal on Solana - programs are usually upgradable so authors can ship fixes. Do not apologize for it. "Trustless" means the documented rules cannot be bypassed, not that the bytecode is frozen.
- One name per role, enforced everywhere (borrower/lender, maker/taker, long/short). Mixing terms mid-document is how readers lose track of who owes what.
- Spell out two-asset flows with concrete examples: "posts USDC as collateral, borrows NVDAx" beats "posts collateral and takes delivery of borrowed tokens".
- Tokens are fungible by default - do not write "fungible token" or explain fungibility. Only qualify for NFTs.
- Drop "tokenized" from economic prose; a tokenized asset is just an asset, unless the act of representing an offchain asset onchain is itself the subject.
- "Securities" is a legal term - SOL is not a security. Prefer "asset lending" / "token lending" and ask before choosing legal-adjacent framing.

## Tooling and versions

- Use the latest stable Anchor, Rust, TypeScript, Solana Kit, and Kite you can. If a bug appears, prefer upgrading over rolling back.
- Use npm for new JS/TS projects (no extra deps); keep pnpm if the repo already uses it. Do not introduce yarn.
- Official docs: Anchor (anchor-lang.com/docs), LiteSVM, Solana Kite (solanakite.org), Solana Kit (solanakit.com), Anza/Agave (docs.anza.xyz). Use Switchboard and Pyth docs when those oracles are used.

## Dead / deprecated tools to avoid

- Do not use "Solana Labs" docs (replaced by Anza) or "Coral XYZ" docs (Anchor is now maintained by the Solana Foundation). Do not use anything from Project Serum.
- Do not use Switchboard Functions (dead); Switchboard oracles are still fine.
- Do not use Clockwork (dead); for scheduled instruction invocation use TukTuk.
- Do not use `@project-serum/anchor` in new tests - use `@coral-xyz/anchor`. (Some of the team's older vault repos still import the Serum package; treat that as MODIFY, not a pattern to copy.)

---
name: evm-staking-vault
description: Use when planning or implementing staking and yield vault systems in Solidity, including Hardhat project setup, shared router architecture, protocol-specific ERC-4626 vaults, withdrawal capability design, reward harvesting, fee policy, and invariant-driven testing.
---

# Build Staking Vaults

Use this skill as the package overview when the task is to build or extend staking or yield vault systems.

This package is split into focused skills:

- For Hardhat and OpenZeppelin project scaffolding:
  Read [references/project-setup.md](references/project-setup.md)
- For staking vault architecture, router design, ERC-4626 vault boundaries, rewards, fees, and invariants:
  Read [references/architecture.md](references/architecture.md)

Use this top-level overview when the user request is broad and you need to decide whether the work is mainly:

- project setup
- vault architecture design
- protocol-specific vault implementation
- reward and fee design
- testing against invariants

Prefer loading only the subskill that matches the task instead of treating this package as one giant skill.

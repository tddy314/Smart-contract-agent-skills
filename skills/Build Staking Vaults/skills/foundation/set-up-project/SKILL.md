---
name: set-up-project
description: "Set up a Solidity smart contract project with OpenZeppelin Contracts. Use when users need to: (1) create a new Hardhat project, (2) install OpenZeppelin Contracts dependencies for Solidity, or (3) understand Solidity import conventions for OpenZeppelin."
license: MIT
metadata:
  author: OpenZeppelin
  domain: solidity
  category: setup
  frameworks:
    - hardhat
  languages:
    - solidity
    - typescript
---

# Solidity Setup

For existing projects, detect the framework by looking for `hardhat.config.*`.

## Hardhat Setup

- Initialize a project only when starting from an empty directory. Install the maintained Hardhat v2 npm tag before running the initializer.

```bash
npm init -y
npm install --save-dev hardhat@hh2
npx hardhat init
```

- `hardhat@hh2` is the npm dist-tag for the maintained Hardhat v2 release line.
- For Hardhat v2, use `npx hardhat init`; `npx hardhat --init` is the Hardhat v3 initializer flow.

- Default choices:
  - Project type: TypeScript
  - Test runner: Mocha + Chai
  - Test command: `npx hardhat test`
  - Compile command: `npx hardhat compile`
  - Network config: defined in `hardhat.config.ts`

- If the generated sample includes Hardhat Ignition or `@nomicfoundation/hardhat-toolbox`, remove those deploy/plugin conventions before applying this baseline. This setup uses `hardhat-deploy` v1 with ethers v5.

- Install OpenZeppelin Contracts:

```bash
npm install @openzeppelin/contracts
```

- If using upgradeable contracts, also install the upgradeable variant:

```bash
npm install @openzeppelin/contracts-upgradeable
```

- Always use the Hardhat v2-compatible `hardhat-deploy` v1 line for deployment scripts.
  - Install:
    ```bash
    npm install --save-dev hardhat-deploy@^0.12 @nomiclabs/hardhat-ethers@^2.2 ethers@^5 dotenv
    ```
  - Use:
    ```bash
    npx hardhat deploy --network <network alias in hardhat config>
    Example: npx hardhat deploy --network base
    ```
  - Do not install `hardhat-deploy@2` in a Hardhat v2 project; its current API targets Hardhat v3.

## Hardhat Config Baseline

Use this baseline when creating or updating `hardhat.config.ts`:

```ts
import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import * as dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BASE_RPC_URL = process.env.BASE_RPC_URL || "";
const accounts = PRIVATE_KEY ? [PRIVATE_KEY] : [];

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: {
      default: 0,
    },
    admin: {
      default: 1,
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
    base: {
      url: BASE_RPC_URL,
      chainId: 8453,
      accounts,
      live: true,
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
    deploy: "./deploy",
    deployments: "./deployments",
  },
};

export default config;
```

- Keep secrets in `.env`; never hardcode private keys or RPC credentials.
- Store `PRIVATE_KEY` with its `0x` prefix and never add another prefix inside `hardhat.config.ts`.
- Refuse live network deployments unless the required private key and RPC URL are defined.
- Keep `namedAccounts.deployer` stable across environments for deterministic deploy behavior.
- Only add network entries that are actively used.
- Keep Solidity version and optimizer aligned across all contracts in the repo.

## Environment Setup

Create `.env.example` and commit it without secrets:

```dotenv
PRIVATE_KEY=0x...
BASE_RPC_URL=https://...
```

Add local and generated files to `.gitignore`:

```gitignore
.env
node_modules/
artifacts/
cache/
typechain-types/
deployments/hardhat/
deployments/localhost/
```

- Commit `deployments/<live-network>/` only when deployment records are part of the project's source of truth.
- Never commit local or fork deployment outputs.

## Required Repository Files

Create or verify these files and directories during setup:

```text
hardhat.config.ts
tsconfig.json
package.json
.env.example
.gitignore
contracts/
deploy/
test/
```

## Recommended Project Structure

### Folder Structure

```text
contracts/
├─ access/
├─ core/
├─ interfaces/
├─ libraries/
├─ mocks/
├─ tokens/
├─ utils/
└─ vaults/

test/
├─ unit/
├─ integration/
├─ fixtures/
└─ helpers/

deploy/
├─ 00-deploy-core.ts
├─ 01-deploy-vaults.ts
└─ 99-post-deploy.ts

tasks/
├─ accounts.ts
└─ verify.ts

scripts/
├─ upgrade/
└─ utils/

deployments/
typechain-types/

docs/
├─ architecture/
├─ security/
└─ diagrams/

.agent/
└─ skills/

artifacts/
cache/
node_modules/
```

### Hardhat Conventions

- Use `contracts/` for Solidity source files.
- Use TypeScript (`hardhat.config.ts`, tests, deploy scripts, tasks) by default.
- Use `deploy/` for `hardhat-deploy` scripts and name files with numeric prefixes for deterministic order.
- Use `scripts/` only for one-off operational scripts (upgrade, migration helpers, data fixes).
- Keep environment-specific outputs inside `deployments/<network>/` and never hand-edit generated deployment JSON.
- Keep custom CLI commands in `tasks/`; prefer tasks over ad-hoc script logic when command reuse is expected.
- Use OpenZeppelin Contracts for standard implementations.
- Prefer npm for dependency management and lockfile consistency.

### Rules

- Do not introduce Foundry-specific structure.
- Do not create `src/` or `script/` folders.
- Keep production contracts separated from mocks.
- Prefer existing folder conventions before creating new directories.

## Setup Validation

The setup is complete only after these commands succeed:

```bash
npx hardhat compile
npx hardhat test
npx hardhat deploy --network hardhat
```

- Confirm that generated artifacts are ignored by Git.
- Confirm that live deployments require environment-provided credentials.

## Import Conventions

- Standard: `@openzeppelin/contracts/token/ERC20/ERC20.sol`
- Upgradeable: `@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol`
- Use upgradeable variants only when deploying behind proxies; otherwise use standard contracts.

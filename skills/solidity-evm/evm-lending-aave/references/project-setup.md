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

## Hardhat Config Baseline

Use this baseline when creating or updating `hardhat.config.ts`:

```ts
import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import * as dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY;
const RPC_URL = process.env.RPC_URL || "";
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
    localfork: {
      url: RPC_URL,
      accounts,
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

## Recommended Project Structure

```text
contracts/
├─ core/
├─ config/
├─ interfaces/
├─ libraries/
├─ oracle/
├─ rates/
├─ tokens/
└─ mocks/

test/
├─ unit/
├─ integration/
├─ invariant/
└─ helpers/

deploy/
docs/
artifacts/
cache/
node_modules/
```

## Rules

- Keep secrets in `.env`; never hardcode private keys or RPC credentials.
- Use `contracts/` for Solidity source files.
- Prefer TypeScript for config, tests, and deploy scripts.
- Keep production contracts separate from mocks.
- Do not introduce Foundry-specific structure unless the user explicitly wants it.
- Validate the setup with `npx hardhat compile` and `npx hardhat test`.

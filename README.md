# DeFi Stablecoin Protocol

A Basic decentralized stablecoin protocol built with Solidity and Foundry that maintains price stability through overcollateralization.

## Overview

This project implements a decentralized stablecoin (DSC) that is:

- **Collateral-backed**: Backed by cryptocurrency assets (WETH and WBTC)
- **Overcollateralized**: Requires more collateral value than minted stablecoin value
- **Algorithmic**: Uses smart contracts to maintain price stability
- **Decentralized**: No central authority controls the protocol

## Key Features

- **Mint DSC**: Users can mint stablecoin by depositing collateral
- **Burn DSC**: Users can burn stablecoin to reduce their debt
- **Deposit/Redeem Collateral**: Manage collateral positions
- **Liquidation Protection**: Maintains health factor above minimum threshold
- **Price Feeds**: Uses Chainlink oracles for accurate asset pricing

## Architecture

### Core Contracts

- **`DecentralizedStableCoin.sol`**: ERC20 stablecoin token contract
- **`DSCEngine.sol`**: Main protocol engine handling collateral, minting, and liquidations

### Supported Collateral

- WETH (Wrapped Ethereum)
- WBTC (Wrapped Bitcoin)

## How It Works

1. **Deposit Collateral**: Users deposit supported cryptocurrency as collateral
2. **Mint Stablecoin**: Based on collateral value, users can mint DSC tokens
3. **Maintain Health Factor**: Users must keep their position overcollateralized
4. **Liquidation**: Undercollateralized positions can be liquidated by other users

## Key Functions

### DSCEngine Contract

- `depositCollateralAndMintDsc()`: Deposit collateral and mint DSC in one transaction
- `depositCollateral()`: Add collateral to your position
- `mintDsc()`: Mint DSC tokens against your collateral
- `burnDsc()`: Burn DSC tokens to reduce debt
- `redeemCollateral()`: Withdraw collateral from your position
- `liquidate()`: Liquidate undercollateralized positions

## Installation & Setup

```bash
# Clone the repository
git clone <repository-url>
cd defi-stablecoin

# Install dependencies (using Makefile)
make install

# Or install manually
forge install

# Build the project
make build
```

### Environment Setup

For testnet deployment, create a `.env` file in the root directory:

```bash
# .env
SEPOLIA_RPC_URL=your_sepolia_rpc_url
PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_etherscan_api_key
```

⚠️ **Never commit your `.env` file or expose private keys!**

## Usage

### Using Makefile (Recommended)

The project includes a Makefile with convenient commands:

```bash
# Install all dependencies
make install

# Build the project
make build

# Run tests
make test

# Generate coverage report
make coverage

# Format code
make format

# Clean build artifacts
make clean

# Start local Anvil node
make anvil

# Deploy to local network
make deploy

# Deploy to Sepolia testnet (requires .env setup)
make deploy ARGS="--network sepolia"

# Get help with available commands
make help
```

### Manual Forge Commands

```bash
# Compile contracts
forge build

# Run tests
forge test

# Format code
forge fmt

# Generate gas snapshots
forge snapshot
```

## Built With

- [Solidity](https://soliditylang.org/) - Smart contract language
- [Foundry](https://book.getfoundry.sh/) - Development framework
- [OpenZeppelin](https://openzeppelin.com/) - Security-focused contract library
- [Chainlink](https://chain.link/) - Price feed oracles

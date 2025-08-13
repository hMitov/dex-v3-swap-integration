## Overview

This repository implements a comprehensive Uniswap V3 swapping solution that combines the power of Uniswap's concentrated liquidity with intelligent slippage protection using Time-Weighted Average Price (TWAP) oracles. The system is designed for both single-hop and multi-hop swaps with automatic slippage bounds when users pass 0 for min/max amounts.

**Key Features:**
- **Single-hop and multi-hop swaps** on Uniswap V3 with exact input/output
- **TWAP-backed slippage bounds** (automatic when user passes 0)
- **ETH↔WETH handling** (zero address automatically mapped to WETH)
- **Access control & pausing** for operational security
- **Pair allow-list** via TWAP provider (bidirectional based on normalized pairId)
- **Reentrancy protection** and approval reset to 0

**TWAP Auto-Calculation:**
- **Exact Input Swaps:** When `amountOutMinimum = 0`, TWAP is automatically calculated to determine the minimum output
- **Exact Output Swaps:** When `amountInMaximum = 0`, TWAP is automatically calculated to determine the maximum input

## Architecture

The system operates through a clean separation of concerns where the `UniswapV3Swapper` handles swap execution while the `TWAPPriceProvider` manages price feeds and pair validation.

```
User → UniswapV3Swapper → Uniswap V3 Router/Pool
                ↓
        TWAPPriceProvider (TWAP consult)
                ↓
        ETH/WETH wrapping/unwrapping
```

**Core Components:**
- `_normalizeToken`: Converts zero address to WETH for ETH handling
- `_takeFunds`: Manages token/ETH input collection
- `_sendFunds`: Handles output distribution (ETH unwrapping, token transfer)
- `_approveToken`: Manages router approvals with reset to 0
- `_twapMinOut/_twapMaxIn`: Derives slippage bounds from TWAP
- `_buildPath/_buildReversedPath`: Constructs multihop paths

## Contracts

### TWAPPriceProvider.sol

**Purpose:** Fetches Uniswap V3 TWAP using OracleLibrary.consult and getQuoteAtTick.

**Roles:** `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`, `PAUSER_ROLE`

**Key Storage:**
- `tokenPairs`: Mapping from pair ID to TokenPair info
- `defaultTwapPeriod`: 900 seconds (15 minutes)
- `MAX_TWAP_PERIOD`: 86400 seconds (24 hours)

**APIs:**
- `addTokenPair(token0, token1, pool, fee)`: Register new trading pair
- `removeTokenPair(token0, token1, fee)`: Remove trading pair
- `isPairSupported(tokenA, tokenB, fee)`: Check if pair is whitelisted
- `getTwapPrice(tokenIn, tokenOut, amountIn, fee, period)`: Get TWAP quote

**Pair ID Normalization:** `_getPairId` sorts addresses to make whitelist bidirectional.

### UniswapV3Swapper.sol

**Purpose:** Exact-input/output single-hop and multihop swaps with optional TWAP-derived min/max bounds.

**Roles:** `ADMIN_ROLE`, `PAUSER_ROLE`

**Configuration:**
- `twapPeriod`: 0 uses provider default (900s), configurable via `setTwapPeriod()`
- `twapSlippageBps`: Default 100 (1.00%), configurable via `setTwapSlippageBps()`

**Key Functions:**
- `swapExactInputSingle` & `swapExactOutputSingle`
- `swapExactInputMultihop` & `swapExactOutputMultihop`
- Internal helpers for funds, approvals, TWAP derivation, and path building

**Safety Features:**
- Reentrancy guard
- Approval reset to 0
- Explicit deadlines
- Pair allow-list checks
- Pausable operations

## TWAP Behavior & Slippage Protection

**Automatic TWAP Calculation:**
The system automatically calculates TWAP-based slippage bounds when users pass 0 for min/max amounts, providing intelligent slippage protection without manual calculations.

**Exact Input Swaps (`amountOutMinimum = 0`):**
- TWAP price is consulted from the specified pool
- Minimum output is calculated as: `TWAP_Price * (1 - twapSlippageBps/10000)`
- Example: With 100 bps (1%) slippage, if TWAP shows 1000 USDC for 1 ETH, minimum becomes 990 USDC

**Exact Output Swaps (`amountInMaximum = 0`):**
- TWAP price is consulted from the specified pool  
- Maximum input is calculated as: `TWAP_Price * (1 + twapSlippageBps/10000)`
- Example: With 100 bps (1%) slippage, if TWAP shows 1 ETH for 1000 USDC, maximum becomes 1.01 ETH

**Configuration:**
- `twapSlippageBps`: Configurable slippage buffer (default: 100 = 1.00%)
- `twapPeriod`: TWAP calculation period in seconds (0 = use provider default of 900s)
- Both parameters can be adjusted by contract admin via `setTwapSlippageBps()` and `setTwapPeriod()`

**Benefits:**
- **User Experience:** No need to manually calculate slippage bounds
- **Safety:** Automatic protection against price manipulation
- **Flexibility:** Users can still override with manual min/max values
- **Gas Efficiency:** Single TWAP call instead of multiple price checks

## Configuration (.env)

Create a `.env` file with the following configuration:

```bash
# RPC & Keys
DEPLOYER_PRIVATE_KEY=                # deployer key (no 0x prefix)
ETHEREUM_SEPOLIA_RPC_URL=            # Sepolia testnet RPC
MAINNET_RPC_URL=                     # Mainnet RPC

# Core addresses (Sepolia testnet)
SEPOLIA_SWAP_ROUTER_ADDRESS=         # Uniswap V3 SwapRouter on Sepolia
SEPOLIA_FACTORY_ADDRESS=             # Uniswap V3 Factory on Sepolia
SEPOLIA_WETH_ADDRESS=                # WETH on Sepolia
TWAP_PROVIDER_ADDRESS=               # Deployed TWAP provider address

# Token addresses (Sepolia testnet)
SEPOLIA_USDC=                        # USDC token on Sepolia
SEPOLIA_USDT=                        # USDT token on Sepolia
SEPOLIA_DAI=                         # DAI token on Sepolia
```

**Network Addresses:**

| Network | Uniswap V3 Router | WETH | Factory | USDC | USDT | DAI |
|---------|-------------------|------|---------|------|------|-----|
| Mainnet | 0xE592427A0AEce92De3Edee1F18E0157C05861564 | 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 | 0x1F98431c8aD98523631AE4a59f267346ea31F984 | - | - | - |
| Sepolia | 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E | 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14 | 0x0227628f3F023bb0B980b67D528571c95c6DaC1c | 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 | 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0 | 0x68194a729C2450ad26072b3D33ADaCbcef39D574 |

*Note: The Sepolia addresses above are from your configuration. For mainnet, verify addresses before deployment.*

## Install & Build

**Prerequisites:**
- [Foundry](https://getfoundry.sh/) (`curl -L https://foundry.paradigm.xyz | bash`, then `foundryup`)
- Node.js (optional, for additional tooling)

**Build Commands:**
```bash
forge install
forge build
```

**Note:** Solidity 0.7.6 is pinned; OpenZeppelin v3.x may emit constructor visibility warnings (harmless).

## Testing

**Run Tests:**
```bash
forge test -vvv
```

**Test Coverage:**
- **TWAPPriceProvider:** Add/remove pairs, consult TWAP (mock/fork), role/pausing checks
- **UniswapV3Swapper:**
  - Single-hop exact-input/output with TWAP-derived bounds (when min/max = 0)
  - Multihop exact-input/output with chained TWAP bounds
  - ETH/WETH wrap/unwrap paths
  - Pausing and role checks (grant/revoke)
  - Reverts on invalid deadlines, fees, unsupported pairs, etc.

**Foundry Configuration:**
- Solidity 0.7.6 with OpenZeppelin v3.x and Uniswap V3 dependencies
- Standard library remappings for clean imports

## Deployment

**Deployment Scripts:**

1. **DeployTWAPPriceProvider.s.sol** — Deploy provider and set initial pairs
2. **DeployUniswapV3Swapper.s.sol** — Deploy swapper with router, WETH, provider
3. **EnvLoader.s.sol** — Base class for environment variable loading

**Deployment Commands:**
```bash
# Load environment variables
source .env

# Deploy TWAP Price Provider
forge script script/DeployTWAPPriceProvider.s.sol:DeployTWAPPriceProviderScript \
  --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast --verify -vvvv

# Deploy Uniswap V3 Swapper
forge script script/DeployUniswapV3Swapper.s.sol:DeployUniswapV3SwapperScript \
  --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast --verify -vvvv
```

**Verification:** Use `--verify` flag with Etherscan API key for contract verification.

## Usage Examples

### Exact-Input Single-Hop (WETH→USDC)
With `amountOutMinimum=0` for automatic TWAP slippage calculation:
```bash
cast send <SWAPPER_ADDRESS> "swapExactInputSingle(address,address,uint256,uint24,uint256,uint256)" \
  $SEPOLIA_WETH_ADDRESS $SEPOLIA_USDC 100000000000000000 3000 $DEADLINE 0 \
  --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $ETHEREUM_SEPOLIA_RPC_URL
```
**Note:** When `amountOutMinimum=0`, the system automatically calculates the minimum output using TWAP price minus the configured slippage buffer.

### Exact-Output Single-Hop
With `amountInMaximum=0` for automatic TWAP slippage calculation:
```bash
cast send <SWAPPER_ADDRESS> "swapExactOutputSingle(address,address,uint256,uint256,uint24,uint256)" \
  $SEPOLIA_WETH_ADDRESS $SEPOLIA_USDC 1000000 0 3000 $DEADLINE \
  --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $ETHEREUM_SEPOLIA_RPC_URL
```
**Note:** When `amountInMaximum=0`, the system automatically calculates the maximum input using TWAP price plus the configured slippage buffer.

### Multihop Exact-Input
Path: [WETH, USDC, DAI] with fees [3000, 10000]:
```bash
cast send <SWAPPER_ADDRESS> "swapExactInputMultihop(address[],uint24[],uint256,uint256,uint256)" \
  "[$SEPOLIA_WETH_ADDRESS,$SEPOLIA_USDC,$SEPOLIA_DAI]" "[3000,10000]" 100000000000000000 0 $DEADLINE \
  --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $ETHEREUM_SEPOLIA_RPC_URL
```
**Note:** When `amountOutMinimum=0`, TWAP is calculated for the final hop to determine the minimum output across the entire path.

### Multihop Exact-Output
Reversed path encoding with `amountInMaximum=0`:
```bash
cast send <SWAPPER_ADDRESS> "swapExactOutputMultihop(address[],uint24[],uint24[],uint256,uint256,uint256)" \
  "[$SEPOLIA_DAI,$SEPOLIA_USDC,$SEPOLIA_WETH_ADDRESS]" "[10000,3000]" 1000000 0 $DEADLINE \
  --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $ETHEREUM_SEPOLIA_RPC_URL
```
**Note:** When `amountInMaximum=0`, TWAP is calculated for the first hop to determine the maximum input across the entire path.

**Notes:**
- **Deadlines:** UTC timestamp (e.g., `$(date -d '+1 hour' +%s)`)
- **Fee Tiers:** 500 (0.05%), 3000 (0.3%), 10000 (1%)
- **TWAP Auto:** Pass 0 for min/max to use TWAP-derived bounds
  - `amountOutMinimum=0` → Automatic TWAP calculation for minimum output
  - `amountInMaximum=0` → Automatic TWAP calculation for maximum input
- **Pair Validation:** Swaps revert if pair not allowed by TWAP provider

## Security & Operational Notes

**TWAP Considerations:**
- TWAP is a lagging signal; set `twapSlippageBps` appropriately
- **Recommended ranges:** 50-200 bps (0.5%-2.0%) for stable pairs, 200-500 bps (2.0%-5.0%) for volatile pairs

**Access Control:**
- Only grant `PAUSER_ROLE`/`ADMIN_ROLE` to trusted operations
- Consider using a [Safe](https://safe.global/) for multi-sig operations
- Always reset approvals to zero (implemented in contract)

**Bidirectional Whitelist:**
- `_getPairId` sorts addresses for consistent pair identification
- Both `(tokenA, tokenB)` and `(tokenB, tokenA)` map to same pairId

**Common Failure Modes:**
- "Slippage limit exceeded" → Adjust `twapSlippageBps` or use manual bounds
- "Token pair not allowed" → Add pair to TWAP provider allowlist
- "Deadline passed" → Use future timestamp
- "Invalid pool fee" → Use supported fee tiers (500, 3000, 10000)

## Troubleshooting

**"Stack too deep" Errors:**
- Use scoped blocks (already applied in multihop functions)
- Consider breaking complex functions into smaller helpers

**Constructor Visibility Warnings:**
- Solidity 0.7.x with OpenZeppelin v3.x compatibility
- Safe to ignore; doesn't affect functionality

**Fork Testing:**
- Set `FOUNDRY_ETH_RPC_URL` or `RPC_URL` environment variable
- Use `--fork-url` flag for mainnet pool testing
- Ensure sufficient ETH balance for forking

**Gas Optimization:**
- Batch operations where possible
- Use appropriate fee tiers for your use case
- Consider gas price strategies for mainnet deployment

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Disclaimer:** This software is provided "as is" without warranty. Use at your own risk and ensure proper testing before mainnet deployment.

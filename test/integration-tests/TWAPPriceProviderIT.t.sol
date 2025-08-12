// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../../src/TWAPPriceProvider.sol";
import "../../src/interfaces/ITWAPPriceProvider.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

/// @title TWAPPriceProvider Integration Tests
/// @notice Integration tests for TWAPPriceProvider using mainnet fork
contract TWAPPriceProviderITTest is Test {
    ITWAPPriceProvider private priceProvider;

    // Test accounts
    address private user;
    address private admin;

    // Mainnet addresses
    address private constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // Uniswap V3 Pool addresses (mainnet)
    address private constant WETH_USDC_POOL = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8; // 0.3% fee
    address private constant WETH_USDT_POOL = 0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36; // 0.3% fee
    address private constant USDC_USDT_POOL = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6; // 0.01% fee

    // Token interfaces
    IERC20 private weth;
    IERC20 private usdc;
    IERC20 private usdt;
    IERC20 private dai;

    // Fork ID
    uint256 private mainnetFork;

    function setUp() public {
        // Create fork
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        // Set up test accounts
        user = makeAddr("USER");
        admin = makeAddr("ADMIN");

        // Fund accounts with ETH
        vm.deal(user, 100 ether);
        vm.deal(admin, 50 ether);

        // Initialize token contracts
        weth = IERC20(MAINNET_WETH);
        usdc = IERC20(MAINNET_USDC);
        usdt = IERC20(MAINNET_USDT);

        // Deploy TWAPPriceProvider contract
        vm.startPrank(admin);
        priceProvider = new TWAPPriceProvider();
        vm.stopPrank();
    }

    function testSetup() public view {
        assertEq(address(priceProvider) != address(0), true, "TWAPPriceProvider should be deployed");
        assertEq(user.balance, 100 ether, "User should have 100 ETH");
        assertEq(admin.balance, 50 ether, "Admin should have 50 ETH");
        assertEq(address(weth), MAINNET_WETH, "WETH should be initialized");
        assertEq(address(usdc), MAINNET_USDC, "USDC should be initialized");
    }

    function testVerifyPoolAddresses() public view {
        // Uniswap V3 Factory address on mainnet
        address factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

        // Get pool addresses from factory
        address wethUsdcPool = IUniswapV3Factory(factory).getPool(MAINNET_WETH, MAINNET_USDC, 3000);
        address wethUsdtPool = IUniswapV3Factory(factory).getPool(MAINNET_WETH, MAINNET_USDT, 3000);
        address usdcUsdtPool = IUniswapV3Factory(factory).getPool(MAINNET_USDC, MAINNET_USDT, 100);

        // Check if pools exist
        assertTrue(wethUsdcPool != address(0), "WETH-USDC pool should exist");
        assertTrue(wethUsdtPool != address(0), "WETH-USDT pool should exist");
        assertTrue(usdcUsdtPool != address(0), "USDC-USDT pool should exist");

        // Verify pool tokens and fees
        IUniswapV3Pool pool1 = IUniswapV3Pool(wethUsdcPool);
        IUniswapV3Pool pool2 = IUniswapV3Pool(wethUsdtPool);
        IUniswapV3Pool pool3 = IUniswapV3Pool(usdcUsdtPool);

        assertEq(uint256(pool1.fee()), 3000, "WETH-USDC pool should have 0.3% fee");
        assertEq(uint256(pool2.fee()), 3000, "WETH-USDT pool should have 0.3% fee");
        assertEq(uint256(pool3.fee()), 100, "USDC-USDT pool should have 0.01% fee");
    }

    function testCheckPoolLiquidity() public view {
        // Check the actual liquidity of the pools
        IUniswapV3Pool wethUsdcPool = IUniswapV3Pool(WETH_USDC_POOL);
        IUniswapV3Pool wethUsdtPool = IUniswapV3Pool(WETH_USDT_POOL);
        IUniswapV3Pool usdcUsdtPool = IUniswapV3Pool(USDC_USDT_POOL);

        uint128 wethUsdcLiquidity = wethUsdcPool.liquidity();
        uint128 wethUsdtLiquidity = wethUsdtPool.liquidity();
        uint128 usdcUsdtLiquidity = usdcUsdtPool.liquidity();

        assertGt(uint256(wethUsdcLiquidity), 0, "WETH-USDC pool should have liquidity");
        assertGt(uint256(wethUsdtLiquidity), 0, "WETH-USDT pool should have liquidity");
        assertGt(uint256(usdcUsdtLiquidity), 0, "USDC-USDT pool should have liquidity");
    }

    function testAdd_WETH_USDC_Pair() public {
        vm.startPrank(admin);

        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_WETH, WETH_USDC_POOL, 3000);
        assertTrue(priceProvider.isPairSupported(MAINNET_USDC, MAINNET_WETH, 3000));

        vm.stopPrank();
    }

    function testAdd_WETH_USDT_Pair() public {
        vm.startPrank(admin);

        priceProvider.addTokenPair(MAINNET_WETH, MAINNET_USDT, WETH_USDT_POOL, 3000);
        assertTrue(priceProvider.isPairSupported(MAINNET_WETH, MAINNET_USDT, 3000));

        vm.stopPrank();
    }

    function testAdd_USDC_USDT_Pair() public {
        vm.startPrank(admin);

        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_USDT, USDC_USDT_POOL, 100);
        assertTrue(priceProvider.isPairSupported(MAINNET_USDC, MAINNET_USDT, 100));

        vm.stopPrank();
    }

    function testGetTwapPrice_WETHToUSDC() public {
        vm.startPrank(admin);

        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_WETH, WETH_USDC_POOL, 3000);

        uint128 amountIn = 1 ether;
        uint32 twapPeriod = 1800; // 30 minutes
        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(MAINNET_WETH, MAINNET_USDC, amountIn, 3000, twapPeriod);

        assertGt(amountOut, 0, "Should get a positive amount out");
        assertEq(uint256(decimals), 6, "USDC has 6 decimals");

        vm.stopPrank();
    }

    function testGetTwapPrice_USDCToWETH() public {
        vm.startPrank(admin);

        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_WETH, WETH_USDC_POOL, 3000);

        uint128 amountIn = 1000 * 10 ** 6; // 1000 USDC
        uint32 twapPeriod = 1800; // 30 minutes
        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(MAINNET_USDC, MAINNET_WETH, amountIn, 3000, twapPeriod);

        assertGt(amountOut, 0, "Should get a positive amount out");
        assertEq(uint256(decimals), 18, "WETH has 18 decimals");

        vm.stopPrank();
    }

    function testGetTwapPrice_WETHToUSDT() public {
        vm.startPrank(admin);

        priceProvider.addTokenPair(MAINNET_WETH, MAINNET_USDT, WETH_USDT_POOL, 3000);

        uint128 amountIn = 1 ether;
        uint32 twapPeriod = 1800; // 30 minutes
        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(MAINNET_WETH, MAINNET_USDT, amountIn, 3000, twapPeriod);

        assertGt(amountOut, 0, "Should get a positive amount out");
        assertEq(uint256(decimals), 6, "USDT has 6 decimals");

        vm.stopPrank();
    }

    function testGetTwapPrice_USDCToUSDT() public {
        vm.startPrank(admin);

        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_USDT, USDC_USDT_POOL, 100);

        uint128 amountIn = 1000 * 10 ** 6; // 1000 USDC
        uint32 twapPeriod = 1800; // 30 minutes
        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(MAINNET_USDC, MAINNET_USDT, amountIn, 100, twapPeriod);

        assertGt(amountOut, 0, "Should get a positive amount out");
        assertEq(uint256(decimals), 6, "USDT has 6 decimals");

        vm.stopPrank();
    }

    function testGetTwapPriceWithZeroPeriod() public {
        vm.startPrank(admin);

        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_WETH, WETH_USDC_POOL, 3000);

        uint128 amountIn = 1 ether;
        uint32 twapPeriod = 0; // Should use default period
        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(MAINNET_WETH, MAINNET_USDC, amountIn, 3000, twapPeriod);

        assertGt(amountOut, 0, "Should get a positive amount out");
        assertEq(uint256(decimals), 6, "USDC has 6 decimals");

        vm.stopPrank();
    }

    function testGetTwapPriceWithMaximumPeriod() public {
        vm.startPrank(admin);

        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_WETH, WETH_USDC_POOL, 3000);

        uint128 amountIn = 1 ether;
        uint32 twapPeriod = TWAPPriceProvider(address(priceProvider)).MAX_TWAP_PERIOD(); // Maximum period
        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(MAINNET_WETH, MAINNET_USDC, amountIn, 3000, twapPeriod);

        assertGt(amountOut, 0, "Should get a positive amount out");
        assertEq(uint256(decimals), 6, "USDC has 6 decimals");

        vm.stopPrank();
    }

    function testGetTwapPriceWithDifferentAmounts() public {
        vm.startPrank(admin);

        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_WETH, WETH_USDC_POOL, 3000);

        uint128[] memory amounts = new uint128[](3);
        amounts[0] = 0.1 ether; // 0.1 WETH
        amounts[1] = 1 ether; // 1 WETH
        amounts[2] = 10 ether; // 10 WETH

        uint32 twapPeriod = 1800; // 30 minutes

        for (uint256 i = 0; i < amounts.length; i++) {
            (uint256 amountOut, uint8 decimals) =
                priceProvider.getTwapPrice(MAINNET_WETH, MAINNET_USDC, amounts[i], 3000, twapPeriod);

            assertGt(amountOut, 0, "Should get a positive amount out");
            assertEq(uint256(decimals), 6, "USDC has 6 decimals");
        }

        vm.stopPrank();
    }

    function testRemoveTokenPair() public {
        vm.startPrank(admin);

        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_WETH, WETH_USDC_POOL, 3000);
        assertTrue(priceProvider.isPairSupported(MAINNET_USDC, MAINNET_WETH, 3000));

        priceProvider.removeTokenPair(MAINNET_USDC, MAINNET_WETH, 3000);
        assertFalse(priceProvider.isPairSupported(MAINNET_USDC, MAINNET_WETH, 3000));

        vm.stopPrank();
    }

    function testPauseAndUnpause() public {
        vm.startPrank(admin);

        TWAPPriceProvider(address(priceProvider)).pause();
        assertTrue(TWAPPriceProvider(address(priceProvider)).paused());

        TWAPPriceProvider(address(priceProvider)).unpause();
        assertFalse(TWAPPriceProvider(address(priceProvider)).paused());

        vm.stopPrank();
    }

    function testGrantAndRevokePauserRole() public {
        vm.startPrank(admin);

        TWAPPriceProvider(address(priceProvider)).grantPauserRole(user);
        assertTrue(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).PAUSER_ROLE(), user
            )
        );

        TWAPPriceProvider(address(priceProvider)).revokePauserRole(user);
        assertFalse(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).PAUSER_ROLE(), user
            )
        );

        vm.stopPrank();
    }

    function testRoleManagement() public {
        vm.startPrank(admin);

        // Test that deployer has all roles
        assertTrue(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).DEFAULT_ADMIN_ROLE(), admin
            )
        );
        assertTrue(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).ADMIN_ROLE(), admin
            )
        );
        assertTrue(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).PAUSER_ROLE(), admin
            )
        );

        // Test that user doesn't have roles initially
        assertFalse(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).DEFAULT_ADMIN_ROLE(), user
            )
        );
        assertFalse(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).ADMIN_ROLE(), user
            )
        );
        assertFalse(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).PAUSER_ROLE(), user
            )
        );

        vm.stopPrank();
    }

    function testFullWorkflow() public {
        vm.startPrank(admin);

        // 1. Add WETH-USDC pair (USDC is token0, WETH is token1 in the pool)
        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_WETH, WETH_USDC_POOL, 3000);
        assertTrue(priceProvider.isPairSupported(MAINNET_USDC, MAINNET_WETH, 3000));

        // 2. Get TWAP price
        uint128 amountIn = 1 ether;
        uint32 twapPeriod = 1800; // 30 minutes

        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(MAINNET_WETH, MAINNET_USDC, amountIn, 3000, twapPeriod);
        assertGt(amountOut, 0, "Should get a positive amount out");
        assertEq(uint256(decimals), 6, "USDC has 6 decimals");

        // 3. Remove the pair
        priceProvider.removeTokenPair(MAINNET_USDC, MAINNET_WETH, 3000);
        assertFalse(priceProvider.isPairSupported(MAINNET_USDC, MAINNET_WETH, 3000));

        vm.stopPrank();
    }

    function testMultipleOperations() public {
        vm.startPrank(admin);

        // Add multiple pairs (with correct token order)
        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_WETH, WETH_USDC_POOL, 3000);
        priceProvider.addTokenPair(MAINNET_WETH, MAINNET_USDT, WETH_USDT_POOL, 3000);
        priceProvider.addTokenPair(MAINNET_USDC, MAINNET_USDT, USDC_USDT_POOL, 100);

        // Verify all pairs exist
        assertTrue(priceProvider.isPairSupported(MAINNET_USDC, MAINNET_WETH, 3000));
        assertTrue(priceProvider.isPairSupported(MAINNET_WETH, MAINNET_USDT, 3000));
        assertTrue(priceProvider.isPairSupported(MAINNET_USDC, MAINNET_USDT, 100));

        // Get prices for all pairs
        uint128 amountIn = 1 ether;
        uint32 twapPeriod = 1800; // 30 minutes

        (uint256 amountOut1,) = priceProvider.getTwapPrice(MAINNET_WETH, MAINNET_USDC, amountIn, 3000, twapPeriod);
        (uint256 amountOut2,) = priceProvider.getTwapPrice(MAINNET_WETH, MAINNET_USDT, amountIn, 3000, twapPeriod);
        (uint256 amountOut3,) = priceProvider.getTwapPrice(MAINNET_USDC, MAINNET_USDT, 1000 * 10 ** 6, 100, twapPeriod);

        assertGt(amountOut1, 0, "Should get positive amount for WETH-USDC");
        assertGt(amountOut2, 0, "Should get positive amount for WETH-USDT");
        assertGt(amountOut3, 0, "Should get positive amount for USDC-USDT");

        // Remove all pairs
        priceProvider.removeTokenPair(MAINNET_USDC, MAINNET_WETH, 3000);
        priceProvider.removeTokenPair(MAINNET_WETH, MAINNET_USDT, 3000);
        priceProvider.removeTokenPair(MAINNET_USDC, MAINNET_USDT, 100);

        // Verify all pairs are removed
        assertFalse(priceProvider.isPairSupported(MAINNET_USDC, MAINNET_WETH, 3000));
        assertFalse(priceProvider.isPairSupported(MAINNET_WETH, MAINNET_USDT, 3000));
        assertFalse(priceProvider.isPairSupported(MAINNET_USDC, MAINNET_USDT, 100));

        vm.stopPrank();
    }
}

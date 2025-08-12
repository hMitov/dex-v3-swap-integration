// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../../src/TWAPPriceProvider.sol";
import "../../src/interfaces/ITWAPPriceProvider.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/mocks/MockWETH.sol";
import "../../src/mocks/MockUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";

/// @title TWAPPriceProvider Unit Tests
/// @notice Comprehensive tests for TWAPPriceProvider functionality
contract TWAPPriceProviderTest is Test {
    TWAPPriceProvider private priceProvider;
    MockERC20 private tokenA;
    MockERC20 private tokenB;
    MockWETH private weth;

    // Test addresses
    address private constant POOL_ADDRESS = address(0x123);
    address private constant USER = address(0x111);
    address private constant ADMIN = address(0x222);

    // Mock pool for testing
    address private mockPool;

    // Test parameters
    uint24 private constant FEE_TIER = 3000; // 0.3%
    uint32 private constant TWAP_PERIOD = 1800; // 30 minutes
    uint128 private constant AMOUNT_IN = 1 ether;

    event PairAdded(bytes32 indexed pairId, address token0, address token1, address pool, uint24 fee);
    event PairRemoved(bytes32 indexed pairId);
    event TwapPeriodUpdated(uint32 oldPeriod, uint32 newPeriod);
    event PriceQueried(bytes32 indexed pairId, uint256 price, uint32 period);

    function setUp() public {
        vm.startPrank(ADMIN);
        // Deploy TWAP
        priceProvider = new TWAPPriceProvider();
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        weth = new MockWETH();

        // Deploy mock pool
        mockPool = address(new MockUniswapV3Pool(address(tokenA), address(tokenB), FEE_TIER));
        vm.stopPrank();
    }

    function testConstructor() public {
        TWAPPriceProvider newProvider = new TWAPPriceProvider();

        assertEq(uint256(newProvider.defaultTwapPeriod()), 900);
        assertEq(uint256(newProvider.MAX_TWAP_PERIOD()), 86400);
    }

    function testAddTokenPair_SUCCESS() public {
        vm.startPrank(ADMIN);

        vm.expectEmit(true, true, false, true);
        bytes32 pairId = keccak256(abi.encodePacked(address(tokenA), address(tokenB), FEE_TIER));
        emit PairAdded(pairId, address(tokenA), address(tokenB), mockPool, FEE_TIER);

        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        assertTrue(priceProvider.isPairSupported(address(tokenA), address(tokenB), FEE_TIER));

        vm.stopPrank();
    }

    function testAddTokenPairRevertsWhenNotAdmin() public {
        vm.startPrank(USER);

        vm.expectRevert("Caller is not admin");
        priceProvider.addTokenPair(address(tokenA), address(tokenB), POOL_ADDRESS, FEE_TIER);

        vm.stopPrank();
    }

    function testAddTokenPairRevertsWhenPairAlreadyExists() public {
        vm.startPrank(ADMIN);

        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        vm.expectRevert("Pair already exists");
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);

        vm.stopPrank();
    }

    function testRemoveTokenPair_SUCCESS() public {
        vm.startPrank(ADMIN);

        // Add pair first
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);

        // Don't check specific event values since they're calculated internally
        vm.expectEmit(true, true, false, true);
        bytes32 pairId = keccak256(abi.encodePacked(address(tokenA), address(tokenB), FEE_TIER));
        emit PairRemoved(pairId);

        // Remove pair
        priceProvider.removeTokenPair(address(tokenA), address(tokenB), FEE_TIER);

        assertFalse(priceProvider.isPairSupported(address(tokenA), address(tokenB), FEE_TIER));

        vm.stopPrank();
    }

    function testRemoveTokenPairRevertsWhenPairNotFound() public {
        vm.startPrank(ADMIN);

        vm.expectRevert("Pair not found");
        priceProvider.removeTokenPair(address(tokenA), address(tokenB), FEE_TIER);

        vm.stopPrank();
    }

    function testGetTwapPriceRevertsWhenZeroTokenInAddress() public {
        vm.expectRevert("Zero token");
        priceProvider.getTwapPrice(address(0), address(tokenB), AMOUNT_IN, FEE_TIER, TWAP_PERIOD);
    }

    function testGetTwapPriceRevertsWhenTokenInSameAsOut() public {
        vm.expectRevert("Same token");
        priceProvider.getTwapPrice(address(tokenA), address(tokenA), AMOUNT_IN, FEE_TIER, TWAP_PERIOD);
    }

    function testGetTwapPriceRevertsWhenZeroTokenOutAddress() public {
        vm.expectRevert("Zero token");
        priceProvider.getTwapPrice(address(tokenA), address(0), AMOUNT_IN, FEE_TIER, TWAP_PERIOD);
    }

    function testGetTwapPriceRevertsWhenPairNotFound() public {
        vm.expectRevert("Pair not found");
        priceProvider.getTwapPrice(address(tokenA), address(tokenB), AMOUNT_IN, FEE_TIER, TWAP_PERIOD);
    }

    function testGetTwapPriceRevertsWhenInvalidTwapPeriod() public {
        vm.startPrank(ADMIN);
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        vm.stopPrank();

        uint32 invalidPeriod = TWAPPriceProvider(address(priceProvider)).MAX_TWAP_PERIOD() + 1;
        vm.expectRevert("Invalid TWAP period");
        priceProvider.getTwapPrice(address(tokenA), address(tokenB), AMOUNT_IN, FEE_TIER, invalidPeriod);
    }

    function testGetTwapPriceWithZeroPeriod_SUCCESS() public {
        vm.startPrank(ADMIN);
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        vm.stopPrank();

        // Should use default period when 0 is passed
        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(address(tokenA), address(tokenB), AMOUNT_IN, FEE_TIER, 0);

        assertGt(amountOut, 0);
        assertEq(uint256(decimals), uint256(tokenB.decimals()));
    }

    function testGetPairId_SUCCESS() public {
        vm.startPrank(ADMIN);
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        vm.stopPrank();

        assertTrue(priceProvider.isPairSupported(address(tokenA), address(tokenB), FEE_TIER));
        assertTrue(priceProvider.isPairSupported(address(tokenB), address(tokenA), FEE_TIER));

        assertFalse(priceProvider.isPairSupported(address(tokenA), address(tokenB), 500));
    }

    function testIsPairSupported_SUCCESS() public {
        vm.startPrank(ADMIN);
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        vm.stopPrank();

        assertTrue(priceProvider.isPairSupported(address(tokenA), address(tokenB), FEE_TIER));
        assertTrue(priceProvider.isPairSupported(address(tokenB), address(tokenA), FEE_TIER));
        assertFalse(priceProvider.isPairSupported(address(tokenA), address(tokenB), 500));
        assertFalse(priceProvider.isPairSupported(address(tokenA), address(weth), FEE_TIER));
    }

    function testAddTokenPairWithDifferentDecimals_SUCCESS() public {
        MockERC20 tokenC = new MockERC20("Token C", "TKC");
        address mockPoolC = address(new MockUniswapV3Pool(address(tokenA), address(tokenC), FEE_TIER));

        vm.startPrank(ADMIN);
        priceProvider.addTokenPair(address(tokenA), address(tokenC), mockPoolC, FEE_TIER);

        assertTrue(priceProvider.isPairSupported(address(tokenA), address(tokenC), FEE_TIER));
        vm.stopPrank();
    }

    function testMultiplePairs_SUCCESS() public {
        MockERC20 tokenC = new MockERC20("Token C", "TKC");
        address pool2 = address(new MockUniswapV3Pool(address(tokenA), address(tokenC), 500));

        vm.startPrank(ADMIN);

        // Add multiple pairs
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        priceProvider.addTokenPair(address(tokenA), address(tokenC), pool2, 500);

        // Verify both pairs exist
        assertTrue(priceProvider.isPairSupported(address(tokenA), address(tokenB), FEE_TIER));
        assertTrue(priceProvider.isPairSupported(address(tokenA), address(tokenC), 500));

        vm.stopPrank();
    }

    function testAccessControlRevertsNotAdmin() public {
        vm.startPrank(USER);

        vm.expectRevert("Caller is not admin");
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        vm.expectRevert("Caller is not admin");
        priceProvider.removeTokenPair(address(tokenA), address(tokenB), FEE_TIER);

        vm.stopPrank();
    }

    function testGrantAndRevokePauserRole() public {
        vm.startPrank(ADMIN);

        priceProvider.grantPauserRole(USER);
        assertTrue(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).PAUSER_ROLE(), USER
            )
        );
        priceProvider.revokePauserRole(USER);
        assertFalse(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).PAUSER_ROLE(), USER
            )
        );

        vm.stopPrank();
    }

    function testGrantPauserRoleRevertsWhenNotAdmin() public {
        vm.startPrank(USER);

        vm.expectRevert("Caller is not admin");
        priceProvider.grantPauserRole(USER);

        vm.stopPrank();
    }

    function testRevokePauserRoleRevertsWhenNotAdmin() public {
        vm.startPrank(USER);

        vm.expectRevert("Caller is not admin");
        priceProvider.revokePauserRole(USER);

        vm.stopPrank();
    }

    function testPauseAndUnpause() public {
        vm.startPrank(ADMIN);

        priceProvider.pause();
        assertTrue(TWAPPriceProvider(address(priceProvider)).paused());
        priceProvider.unpause();
        assertFalse(TWAPPriceProvider(address(priceProvider)).paused());

        vm.stopPrank();
    }

    function testPauseRevertWhenNotPauser() public {
        vm.startPrank(USER);

        vm.expectRevert("Caller is not pauser");
        priceProvider.pause();

        vm.stopPrank();
    }

    function testUnpauseRevertsWhenNotPauser() public {
        vm.startPrank(ADMIN);
        priceProvider.pause();
        vm.stopPrank();

        vm.startPrank(USER);
        vm.expectRevert("Caller is not pauser");
        priceProvider.unpause();
        vm.stopPrank();
    }

    function testAddTokenPairRevertsWhenInvalidPool() public {
        address invalidPool = address(new MockUniswapV3Pool(address(tokenB), address(tokenA), FEE_TIER));

        vm.startPrank(ADMIN);
        vm.expectRevert("Invalid pool");
        priceProvider.addTokenPair(address(tokenA), address(tokenB), invalidPool, FEE_TIER);
        vm.stopPrank();
    }

    function testAddTokenPairRevertsWhenWrongFee() public {
        address wrongFeePool = address(new MockUniswapV3Pool(address(tokenA), address(tokenB), 500));

        vm.startPrank(ADMIN);
        vm.expectRevert("Invalid pool");
        priceProvider.addTokenPair(address(tokenA), address(tokenB), wrongFeePool, FEE_TIER);
        vm.stopPrank();
    }

    function testGetTwapPriceWithMaximumPeriod_SUCCESS() public {
        vm.startPrank(ADMIN);
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        vm.stopPrank();

        (uint256 amountOut, uint8 decimals) = priceProvider.getTwapPrice(
            address(tokenA), address(tokenB), AMOUNT_IN, FEE_TIER, priceProvider.MAX_TWAP_PERIOD()
        );

        assertGt(amountOut, 0);
        assertEq(uint256(decimals), uint256(tokenB.decimals()));
    }

    function testGetTwapPriceWithDifferentAmounts_SUCCESS() public {
        vm.startPrank(ADMIN);
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        vm.stopPrank();

        // Test with different input amounts
        uint128[] memory amounts = new uint128[](3);
        amounts[0] = 1 ether;
        amounts[1] = 10 ether;
        amounts[2] = 100 ether;

        for (uint256 i = 0; i < amounts.length; i++) {
            (uint256 amountOut, uint8 decimals) =
                priceProvider.getTwapPrice(address(tokenA), address(tokenB), amounts[i], FEE_TIER, TWAP_PERIOD);

            assertGt(amountOut, 0);
            assertEq(uint256(decimals), uint256(tokenB.decimals()));
        }
    }

    function testGetTwapPriceWithWETH_SUCCESS() public {
        address wethPool = address(new MockUniswapV3Pool(address(weth), address(tokenB), FEE_TIER));

        vm.startPrank(ADMIN);
        priceProvider.addTokenPair(address(weth), address(tokenB), wethPool, FEE_TIER);
        vm.stopPrank();

        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(address(weth), address(tokenB), AMOUNT_IN, FEE_TIER, TWAP_PERIOD);

        assertGt(amountOut, 0);
        assertEq(uint256(decimals), uint256(tokenB.decimals()));
    }

    function testGetTwapPriceRevertsWhenOracleNotInitialized() public {
        vm.expectRevert("Pair not found");
        priceProvider.getTwapPrice(address(tokenA), address(tokenB), AMOUNT_IN, FEE_TIER, TWAP_PERIOD);
    }

    function testAddTokenPairRevertsWhenZeroAddress() public {
        vm.startPrank(ADMIN);

        vm.expectRevert("Invalid tokens");
        priceProvider.addTokenPair(address(0), address(tokenB), mockPool, FEE_TIER);
        vm.expectRevert("Invalid tokens");
        priceProvider.addTokenPair(address(tokenA), address(0), mockPool, FEE_TIER);
        vm.expectRevert("Invalid tokens");
        priceProvider.addTokenPair(address(tokenA), address(tokenB), address(0), FEE_TIER);

        vm.stopPrank();
    }

    function testFullWorkflow_SUCCESS() public {
        vm.startPrank(ADMIN);

        // 1. Add token pair
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        assertTrue(priceProvider.isPairSupported(address(tokenA), address(tokenB), FEE_TIER));

        // 2. Get TWAP price
        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(address(tokenA), address(tokenB), AMOUNT_IN, FEE_TIER, TWAP_PERIOD);
        assertGt(amountOut, 0);
        assertEq(uint256(decimals), uint256(tokenB.decimals()));

        // 3. Remove token pair
        priceProvider.removeTokenPair(address(tokenA), address(tokenB), FEE_TIER);
        assertFalse(priceProvider.isPairSupported(address(tokenA), address(tokenB), FEE_TIER));

        vm.stopPrank();
    }

    function testMultipleOperations() public {
        MockERC20 tokenC = new MockERC20("Token C", "TKC");
        MockERC20 tokenD = new MockERC20("Token D", "TKD");
        address poolC = address(new MockUniswapV3Pool(address(tokenA), address(tokenC), FEE_TIER));
        address poolD = address(new MockUniswapV3Pool(address(tokenB), address(tokenD), 500));

        vm.startPrank(ADMIN);

        // Add multiple pairs
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        priceProvider.addTokenPair(address(tokenA), address(tokenC), poolC, FEE_TIER);
        priceProvider.addTokenPair(address(tokenB), address(tokenD), poolD, 500);

        // Verify all pairs exist
        assertTrue(priceProvider.isPairSupported(address(tokenA), address(tokenB), FEE_TIER));
        assertTrue(priceProvider.isPairSupported(address(tokenA), address(tokenC), FEE_TIER));
        assertTrue(priceProvider.isPairSupported(address(tokenB), address(tokenD), 500));

        // Get prices for all pairs
        (uint256 amountOut1,) =
            priceProvider.getTwapPrice(address(tokenA), address(tokenB), AMOUNT_IN, FEE_TIER, TWAP_PERIOD);
        (uint256 amountOut2,) =
            priceProvider.getTwapPrice(address(tokenA), address(tokenC), AMOUNT_IN, FEE_TIER, TWAP_PERIOD);
        (uint256 amountOut3,) =
            priceProvider.getTwapPrice(address(tokenB), address(tokenD), AMOUNT_IN, 500, TWAP_PERIOD);

        assertGt(amountOut1, 0);
        assertGt(amountOut2, 0);
        assertGt(amountOut3, 0);

        // Remove all pairs
        priceProvider.removeTokenPair(address(tokenA), address(tokenB), FEE_TIER);
        priceProvider.removeTokenPair(address(tokenA), address(tokenC), FEE_TIER);
        priceProvider.removeTokenPair(address(tokenB), address(tokenD), 500);

        // Verify all pairs are removed
        assertFalse(priceProvider.isPairSupported(address(tokenA), address(tokenB), FEE_TIER));
        assertFalse(priceProvider.isPairSupported(address(tokenA), address(tokenC), FEE_TIER));
        assertFalse(priceProvider.isPairSupported(address(tokenB), address(tokenD), 500));

        vm.stopPrank();
    }

    function testGrantPauserRoleRevertWhenZeroAddress() public {
        vm.startPrank(ADMIN);

        vm.expectRevert("Zero address not allowed");
        priceProvider.grantPauserRole(address(0));

        vm.stopPrank();
    }

    function testRevokePauserRoleRevertWhenZeroAddress() public {
        vm.startPrank(ADMIN);

        vm.expectRevert("Zero address not allowed");
        priceProvider.revokePauserRole(address(0));

        vm.stopPrank();
    }

    function testGetPairIdWithReversedTokenOrder() public {
        vm.startPrank(ADMIN);

        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        assertTrue(priceProvider.isPairSupported(address(tokenA), address(tokenB), FEE_TIER));

        priceProvider.removeTokenPair(address(tokenA), address(tokenB), FEE_TIER);
        address reversedPool = address(new MockUniswapV3Pool(address(tokenB), address(tokenA), FEE_TIER));

        // Add pair with reversed order - should work the same
        priceProvider.addTokenPair(address(tokenB), address(tokenA), reversedPool, FEE_TIER);
        assertTrue(priceProvider.isPairSupported(address(tokenB), address(tokenA), FEE_TIER));

        vm.stopPrank();
    }

    function testPauseWhenAlreadyPaused() public {
        vm.startPrank(ADMIN);

        priceProvider.pause();
        assertTrue(TWAPPriceProvider(address(priceProvider)).paused());
        vm.expectRevert("Pausable: paused");
        priceProvider.pause();

        vm.stopPrank();
    }

    function testUnpauseWhenNotPaused() public {
        vm.startPrank(ADMIN);

        assertFalse(TWAPPriceProvider(address(priceProvider)).paused());
        vm.expectRevert("Pausable: not paused");
        priceProvider.unpause();

        vm.stopPrank();
    }

    function testGetTwapPriceWithNonZeroPeriod() public {
        vm.startPrank(ADMIN);
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        vm.stopPrank();

        uint32 customPeriod = 3600; // 1 hour
        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(address(tokenA), address(tokenB), AMOUNT_IN, FEE_TIER, customPeriod);
        assertGt(amountOut, 0);
        assertEq(uint256(decimals), uint256(tokenB.decimals()));
    }

    function testGetTwapPriceWithVerySmallAmount() public {
        vm.startPrank(ADMIN);
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        vm.stopPrank();

        uint128 smallAmount = 1; // 1 wei

        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(address(tokenA), address(tokenB), smallAmount, FEE_TIER, TWAP_PERIOD);

        assertGt(amountOut, 0);
        assertEq(uint256(decimals), uint256(tokenB.decimals()));
    }

    function testGetTwapPriceWithVeryLargeAmount() public {
        vm.startPrank(ADMIN);
        priceProvider.addTokenPair(address(tokenA), address(tokenB), mockPool, FEE_TIER);
        vm.stopPrank();

        uint128 largeAmount = type(uint128).max;

        (uint256 amountOut, uint8 decimals) =
            priceProvider.getTwapPrice(address(tokenA), address(tokenB), largeAmount, FEE_TIER, TWAP_PERIOD);

        assertGt(amountOut, 0);
        assertEq(uint256(decimals), uint256(tokenB.decimals()));
    }

    function testAddTokenPairWithReversedTokenOrder() public {
        vm.startPrank(ADMIN);

        // Create pool with tokens in reverse order
        address reversedPool = address(new MockUniswapV3Pool(address(tokenB), address(tokenA), FEE_TIER));

        // Should revert because pool has wrong token order
        vm.expectRevert("Invalid pool");
        priceProvider.addTokenPair(address(tokenA), address(tokenB), reversedPool, FEE_TIER);

        vm.stopPrank();
    }

    function testAddTokenPairWithNonExistentPool() public {
        vm.startPrank(ADMIN);

        // Try to add pair with non-existent pool address
        address nonExistentPool = address(0x9999999999999999999999999999999999999999);

        vm.expectRevert(); // Should revert due to low-level call failure
        priceProvider.addTokenPair(address(tokenA), address(tokenB), nonExistentPool, FEE_TIER);

        vm.stopPrank();
    }

    function testRoleManagement() public {
        vm.startPrank(ADMIN);

        // Test that deployer has all roles
        assertTrue(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).DEFAULT_ADMIN_ROLE(), ADMIN
            )
        );
        assertTrue(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).ADMIN_ROLE(), ADMIN
            )
        );
        assertTrue(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).PAUSER_ROLE(), ADMIN
            )
        );

        // Test that USER doesn't have roles initially
        assertFalse(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).DEFAULT_ADMIN_ROLE(), USER
            )
        );
        assertFalse(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).ADMIN_ROLE(), USER
            )
        );
        assertFalse(
            TWAPPriceProvider(address(priceProvider)).hasRole(
                TWAPPriceProvider(address(priceProvider)).PAUSER_ROLE(), USER
            )
        );

        vm.stopPrank();
    }
}

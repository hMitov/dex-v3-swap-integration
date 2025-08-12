// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../../src/UniswapV3Swapper.sol";
import "../../src/mocks/MockWETH.sol";
import "../../src/mocks/MockSwapRouter.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/mocks/MockUniswapV3Pool.sol"; // Added for callback tests
import "../../src/interfaces/ITWAPPriceProvider.sol";

contract MockTWAPProvider is ITWAPPriceProvider {
    mapping(bytes32 => bool) public supportedPairs;

    function addSupportedPair(address tokenA, address tokenB, uint24 fee) external {
        bytes32 pairId =
            keccak256(abi.encodePacked(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA, fee));
        supportedPairs[pairId] = true;
    }

    function isPairSupported(address tokenA, address tokenB, uint24 fee) external view override returns (bool) {
        bytes32 pairId =
            keccak256(abi.encodePacked(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA, fee));
        return supportedPairs[pairId];
    }

    // Implement other interface functions with default values
    function addTokenPair(address, address, address, uint24) external override {}
    function removeTokenPair(address, address, uint24) external override {}

    function getTwapPrice(address, address, uint128, uint24, uint32) external pure override returns (uint256, uint8) {
        return (1000, 18);
    }

    function defaultTwapPeriod() external pure override returns (uint32) {
        return 900;
    }

    function pause() external override {}
    function unpause() external override {}
    function grantPauserRole(address) external override {}
    function revokePauserRole(address) external override {}
}

// contract UniswapV3SwapperTest is Test {
//     UniswapV3Swapper private swapper;
//     MockSwapRouter private mockRouter;
//     MockWETH private mockWETH;
//     MockTWAPProvider private mockTWAPProvider;
//     MockERC20 private tokenA;
//     MockERC20 private tokenB;
//     MockERC20 private tokenC; // Added for multihop tests

//     address private admin;
//     address private user;
//     address private pauser;

//     uint256 private constant INITIAL_TOKEN_SUPPLY = 1000 ether;

//     function setUp() public {
//         admin = makeAddr("ADMIN");
//         user = makeAddr("USER");
//         pauser = makeAddr("PAUSER");

//         vm.startPrank(admin);

//         mockRouter = new MockSwapRouter();
//         mockWETH = new MockWETH();
//         mockTWAPProvider = new MockTWAPProvider();
//         tokenA = new MockERC20("TokenA", "@Token_A@");
//         tokenB = new MockERC20("TokenB", "@Token_B@");
//         tokenC = new MockERC20("TokenC", "@Token_C@"); // Initialize tokenC

//         swapper = new UniswapV3Swapper(address(mockRouter), address(mockWETH), address(mockTWAPProvider));

//         vm.stopPrank();

//         // Set up supported pairs in TWAP provider
//         mockTWAPProvider.addSupportedPair(address(tokenA), address(tokenB), 3000);
//         mockTWAPProvider.addSupportedPair(address(tokenB), address(tokenC), 3000);
//         mockTWAPProvider.addSupportedPair(address(tokenA), address(tokenC), 3000);
//         mockTWAPProvider.addSupportedPair(address(0), address(tokenA), 3000);
//         mockTWAPProvider.addSupportedPair(address(tokenA), address(0), 3000);
//         mockTWAPProvider.addSupportedPair(address(0), address(tokenB), 3000);
//         mockTWAPProvider.addSupportedPair(address(tokenB), address(0), 3000);
//         mockTWAPProvider.addSupportedPair(address(0), address(tokenC), 3000);
//         mockTWAPProvider.addSupportedPair(address(tokenC), address(0), 3000);

//         tokenA.mint(user, INITIAL_TOKEN_SUPPLY);
//         tokenB.mint(user, INITIAL_TOKEN_SUPPLY);
//         tokenC.mint(user, INITIAL_TOKEN_SUPPLY); // Mint tokenC for multihop tests

//         vm.deal(user, 100 ether);
//         vm.deal(pauser, 10 ether);
//         vm.deal(address(swapper), 1000 ether);
//     }

//     function testConstructorArguments() public view {
//         assertEq(address(swapper.router()), address(mockRouter));
//         assertEq(address(swapper.wETH()), address(mockWETH));
//         assertEq(address(swapper.twapProvider()), address(mockTWAPProvider));
//     }

//     function testRolesAfterConstructor() public view {
//         assertTrue(swapper.hasRole(swapper.DEFAULT_ADMIN_ROLE(), admin));
//         assertTrue(swapper.hasRole(swapper.ADMIN_ROLE(), admin));
//         assertTrue(swapper.hasRole(swapper.PAUSER_ROLE(), admin));
//     }

//     function testPause() public {
//         vm.prank(admin);
//         swapper.grantPauserRole(pauser);

//         vm.prank(pauser);
//         swapper.pause();

//         assertTrue(swapper.paused());
//     }

//     function testUnpause() public {
//         vm.prank(admin);
//         swapper.pause();

//         vm.prank(admin);
//         swapper.unpause();

//         assertFalse(swapper.paused());
//     }

//     function testUnpause_RevertsNotPauser() public {
//         vm.prank(admin);
//         swapper.pause();

//         vm.prank(user);
//         vm.expectRevert("Caller is not pauser");
//         swapper.unpause();
//     }

//     function testGrantPauserRole() public {
//         vm.prank(admin);
//         swapper.grantPauserRole(user);

//         assertTrue(swapper.hasRole(swapper.PAUSER_ROLE(), user));
//     }

//     function testGrantPauserRole_RevertsNotAdmin() public {
//         vm.prank(user);
//         vm.expectRevert("Caller is not admin");
//         swapper.grantPauserRole(user);
//     }

//     function testGrantPauserRole_RevertsZeroAddress() public {
//         vm.prank(admin);
//         vm.expectRevert("Zero address not allowed");
//         swapper.grantPauserRole(address(0));
//     }

//     function test_RevokePauserRole_OnlyAdminCanCall() public {
//         vm.prank(user);
//         vm.expectRevert("Caller is not admin");
//         swapper.revokePauserRole(user);
//     }

//     function testRevokePauserRole() public {
//         vm.prank(admin);
//         swapper.grantPauserRole(user);

//         vm.prank(admin);
//         swapper.revokePauserRole(user);

//         assertFalse(swapper.hasRole(swapper.PAUSER_ROLE(), user));
//     }

//     function testRevokePauserRole_RevertsZeroAddress() public {
//         vm.prank(admin);
//         vm.expectRevert("Zero address not allowed");
//         swapper.revokePauserRole(address(0));
//     }

//     function testSwapExactInput_WithERCTokens_Success() public {
//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = 900;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         // Record initial balances
//         uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputSingle(
//             address(tokenA), address(tokenB), amountIn, poolFee, deadline, amountOutMinimum
//         );

//         // Verify swap result
//         assertEq(amountOut, mockRouter.mockAmountOut());
//         assertGe(amountOut, amountOutMinimum);

//         // Verify user received tokens
//         assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");

//         vm.stopPrank();
//     }

//     function testSwapExactInput_WithETHToERC20_Success() public {
//         uint256 amountIn = 1 ether;
//         uint256 amountOutMinimum = 900;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);

//         vm.prank(user);
//         uint256 amountOut = swapper.swapExactInputSingle{value: amountIn}(
//             address(0), address(tokenB), amountIn, poolFee, deadline, amountOutMinimum
//         );

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         assertGe(amountOut, amountOutMinimum);
//         assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");
//     }

//     function testSwapExactInput_WithERC20ToETH_Success() public {
//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = 900;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         uint256 userETHBalanceBefore = user.balance;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut =
//             swapper.swapExactInputSingle(address(tokenA), address(0), amountIn, poolFee, deadline, amountOutMinimum);

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         assertGe(amountOut, amountOutMinimum);
//         assertEq(user.balance - userETHBalanceBefore, amountOut, "User should receive ETH");

//         vm.stopPrank();
//     }

//     function testSwapExactInput_SameTokenReverts() public {
//         vm.prank(user);
//         vm.expectRevert("tokenIn and tokenOut must differ");
//         swapper.swapExactInputSingle(address(tokenA), address(tokenA), 1000, 3000, block.timestamp + 1 hours, 900);
//     }

//     function testSwapExactInput_ZeroAmountInReverts() public {
//         vm.prank(user);
//         vm.expectRevert("amountIn must be greater than zero");
//         swapper.swapExactInputSingle(address(tokenA), address(tokenB), 0, 3000, block.timestamp + 1 hours, 900);
//     }

//     function testSwapExactInput_InvalidPoolFeeReverts() public {
//         vm.prank(user);
//         vm.expectRevert("Invalid pool fee");
//         swapper.swapExactInputSingle(
//             address(tokenA),
//             address(tokenB),
//             1000,
//             2000, // Invalid fee
//             block.timestamp + 1 hours,
//             900
//         );
//     }

//     function testSwapExactInput_DeadlinePassedReverts() public {
//         vm.prank(user);
//         vm.expectRevert("Deadline passed");
//         swapper.swapExactInputSingle(
//             address(tokenA),
//             address(tokenB),
//             1000,
//             3000,
//             block.timestamp - 1, // Past deadline
//             900
//         );
//     }

//     function testSwapExactInput_ETHAmountMismatchReverts() public {
//         vm.prank(user);
//         vm.expectRevert("ETH amount mismatch");
//         swapper.swapExactInputSingle{value: 0.5 ether}(
//             address(0),
//             address(tokenB),
//             1 ether, // Different amount
//             3000,
//             block.timestamp + 1 hours,
//             900
//         );
//     }

//     function testSwapExactInput_ETHNotExpectedReverts() public {
//         vm.prank(user);
//         vm.expectRevert("ETH not expected");
//         swapper.swapExactInputSingle{value: 1 ether}(
//             address(tokenA), address(tokenB), 1000, 3000, block.timestamp + 1 hours, 900
//         );
//     }

//     function testSwapExactInput_SlippageExceededReverts() public {
//         mockRouter.setAmountOut(800); // Less than minimum

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), 1000);

//         vm.expectRevert("Slippage limit exceeded");
//         swapper.swapExactInputSingle(address(tokenA), address(tokenB), 1000, 3000, block.timestamp + 1 hours, 900);
//         vm.stopPrank();
//     }

//     function testSwapExactInput_WhenPausedReverts() public {
//         vm.prank(admin);
//         swapper.pause();

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), 1000);

//         vm.expectRevert();
//         swapper.swapExactInputSingle(address(tokenA), address(tokenB), 1000, 3000, block.timestamp + 1 hours, 900);
//         vm.stopPrank();
//     }

//     // // ============ SwapExactOutputSingle Tests ============

//     function testSwapExactOutput_ERC20ToERC20_Success() public {
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2000;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         uint256 amountIn = swapper.swapExactOutputSingle(
//             address(tokenA), address(tokenB), amountOut, amountInMaximum, poolFee, deadline
//         );

//         assertEq(amountIn, mockRouter.mockAmountIn());
//         assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
//         assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");

//         vm.stopPrank();
//     }

//     function testSwapExactOutput_ETHToERC20_Success() public {
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2 ether;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);

//         vm.prank(user);
//         uint256 amountIn = swapper.swapExactOutputSingle{value: amountInMaximum}(
//             address(0), address(tokenB), amountOut, amountInMaximum, poolFee, deadline
//         );

//         assertEq(amountIn, mockRouter.mockAmountIn());
//         assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
//         assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");
//     }

//     function testSwapExactOutput_ERC20ToETH_Success() public {
//         uint256 amountOut = 1 ether;
//         uint256 amountInMaximum = 2000;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         uint256 userETHBalanceBefore = user.balance;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         uint256 amountIn =
//             swapper.swapExactOutputSingle(address(tokenA), address(0), amountOut, amountInMaximum, poolFee, deadline);

//         assertEq(amountIn, mockRouter.mockAmountIn());
//         assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
//         assertEq(user.balance - userETHBalanceBefore, amountOut, "User should receive ETH");
//         vm.stopPrank();
//     }

//     function testSwapExactOutput_SameTokenReverts() public {
//         vm.prank(user);
//         vm.expectRevert("tokenIn and tokenOut must differ");
//         swapper.swapExactOutputSingle(address(tokenA), address(tokenA), 1000, 2000, 3000, block.timestamp + 1 hours);
//     }

//     function testSwapExactOutput_DeadlinePassedReverts() public {
//         vm.prank(user);
//         vm.expectRevert("Deadline passed");
//         swapper.swapExactOutputSingle(address(tokenA), address(tokenB), 1000, 2000, 3000, block.timestamp - 1);
//     }

//     function testSwapExactOutput_InvalidAmountsReverts() public {
//         vm.prank(user);
//         vm.expectRevert("Invalid amounts");
//         swapper.swapExactOutputSingle(
//             address(tokenA),
//             address(tokenB),
//             0, // Invalid amountOut
//             2000,
//             3000,
//             block.timestamp + 1 hours
//         );
//     }

//     function testSwapExactOutput_InvalidPoolFeeReverts() public {
//         vm.prank(user);
//         vm.expectRevert("Invalid pool fee");
//         swapper.swapExactOutputSingle(
//             address(tokenA),
//             address(tokenB),
//             1000,
//             2000,
//             2000, // Invalid fee
//             block.timestamp + 1 hours
//         );
//     }

//     function testSwapExactOutput_InsufficientETHReverts() public {
//         vm.prank(user);
//         vm.expectRevert("Insufficient ETH sent");
//         swapper.swapExactOutputSingle{value: 1 ether}(
//             address(0),
//             address(tokenB),
//             1000,
//             2 ether, // More than sent
//             3000,
//             block.timestamp + 1 hours
//         );
//     }

//     function testSwapExactOutput_ETHNotExpectedReverts() public {
//         vm.prank(user);
//         vm.expectRevert("ETH not expected");
//         swapper.swapExactOutputSingle{value: 1 ether}(
//             address(tokenA), address(tokenB), 1000, 2000, 3000, block.timestamp + 1 hours
//         );
//     }

//     function testSwapExactOutput_WhenPausedReverts() public {
//         vm.prank(admin);
//         swapper.pause();

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), 2000);

//         vm.expectRevert();
//         swapper.swapExactOutputSingle(address(tokenA), address(tokenB), 1000, 2000, 3000, block.timestamp + 1 hours);
//         vm.stopPrank();
//     }

//     // ============ Allowlist Tests ============

//     function testTWAPProviderIntegration_Success() public view {
//         // Test that the TWAP provider is properly integrated
//         assertTrue(mockTWAPProvider.isPairSupported(address(tokenA), address(tokenB), 3000));
//         assertTrue(mockTWAPProvider.isPairSupported(address(0), address(tokenA), 3000));
//         assertFalse(mockTWAPProvider.isPairSupported(address(tokenA), address(tokenB), 5000)); // Different fee
//     }

//     function testTWAPProviderIntegration_RevertsUnsupportedPair() public {
//         // Create a new token that's not supported
//         MockERC20 newToken = new MockERC20("NewToken", "NEW");

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), 1000);

//         vm.expectRevert("Token pair not allowed");
//         swapper.swapExactInputSingle(address(tokenA), address(newToken), 1000, 3000, block.timestamp + 1 hours, 900);
//         vm.stopPrank();
//     }

//     function testTWAPProviderIntegration_RevertsUnsupportedFee() public {
//         vm.startPrank(user);
//         tokenA.approve(address(swapper), 1000);

//         vm.expectRevert("Token pair not allowed");
//         swapper.swapExactInputSingle(address(tokenA), address(tokenB), 1000, 5000, block.timestamp + 1 hours, 900);
//         vm.stopPrank();
//     }

//     // ============ Multihop Tests ============

//     function testSwapExactInputMultihop_ERC20ToERC20ToERC20_Success() public {
//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = 800;
//         uint24[] memory poolFees = new uint24[](2);
//         poolFees[0] = 3000; // First hop fee
//         poolFees[1] = 3000; // Second hop fee

//         address[] memory tokens = new address[](3);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);
//         tokens[2] = address(tokenC);

//         mockRouter.setFinalToken(address(tokenC));

//         uint256 deadline = block.timestamp + 1 hours;
//         uint256 userTokenCBalanceBefore = tokenC.balanceOf(user);

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputMultihop(tokens, poolFees, amountIn, amountOutMinimum, deadline);

//         assertEq(amountOut, mockRouter.mockAmountOut(), "Should get expected amount out");
//         assertGt(amountOut, amountOutMinimum, "Should meet minimum output");
//         assertEq(tokenC.balanceOf(user) - userTokenCBalanceBefore, amountOut, "User should receive tokens");
//         vm.stopPrank();
//     }

//     function testSwapExactInputMultihop_ETHToERC20ToERC20_Success() public {
//         uint256 amountIn = 1 ether;
//         uint256 amountOutMinimum = 800;
//         uint24[] memory poolFees = new uint24[](2);
//         poolFees[0] = 3000; // First hop fee
//         poolFees[1] = 3000; // Second hop fee

//         address[] memory tokens = new address[](3);
//         tokens[0] = address(0); // ETH
//         tokens[1] = address(tokenA);
//         tokens[2] = address(tokenB);

//         // Configure mock router to return tokenB
//         mockRouter.setFinalToken(address(tokenB));

//         uint256 deadline = block.timestamp + 1 hours;
//         uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);
//         uint256 userETHBalanceBefore = user.balance;

//         vm.startPrank(user);

//         uint256 amountOut =
//             swapper.swapExactInputMultihop{value: amountIn}(tokens, poolFees, amountIn, amountOutMinimum, deadline);

//         assertEq(amountOut, mockRouter.mockAmountOut(), "Should get expected amount out");
//         assertGt(amountOut, amountOutMinimum, "Should meet minimum output");
//         assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");
//         assertLt(user.balance, userETHBalanceBefore, "User should have spent ETH");
//         vm.stopPrank();
//     }

//     function testSwapExactInputMultihop_RevertsInsufficientTokens() public {
//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn - 1); // Insufficient approval

//         vm.expectRevert();
//         swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
//         vm.stopPrank();
//     }

//     function testSwapExactInputMultihop_RevertsPairNotAllowed() public {
//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](2);
//         poolFees[0] = 3000;
//         poolFees[1] = 3000;

//         // Create a new token that's not in the allowlist
//         MockERC20 newToken = new MockERC20("NewToken", "NEW");

//         address[] memory tokens = new address[](3);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);
//         tokens[2] = address(newToken); // tokenB to newToken is not allowed

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert("Token pair not allowed");
//         swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
//         vm.stopPrank();
//     }

//     function testSwapExactInputMultihop_RevertsInvalidPathLength() public {
//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](1); // Only 1 token
//         tokens[0] = address(tokenA);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert("At least 2 tokens required");
//         swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
//         vm.stopPrank();
//     }

//     function testSwapExactInputMultihop_RevertsInvalidFeesLength() public {
//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](1); // Only 1 fee for 2 hops
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](3);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);
//         tokens[2] = address(tokenC);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert("Pool fees length must match hops");
//         swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
//         vm.stopPrank();
//     }

//     function testSwapExactInputMultihop_RevertsZeroAmountIn() public {
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), 1000);

//         vm.expectRevert("amountIn must be greater than zero");
//         swapper.swapExactInputMultihop(
//             tokens,
//             poolFees,
//             0, // Zero amount
//             800,
//             deadline
//         );
//         vm.stopPrank();
//     }

//     function testSwapExactInputMultihop_RevertsDeadlinePassed() public {
//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);

//         uint256 deadline = block.timestamp - 1; // Past deadline

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert("Deadline passed");
//         swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
//         vm.stopPrank();
//     }

//     function testSwapExactInputMultihop_RevertsWhenPaused() public {
//         vm.prank(admin);
//         swapper.pause();

//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert();
//         swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
//         vm.stopPrank();
//     }

//     function testSwapExactInputMultihop_RevertsSlippageExceeded() public {
//         mockRouter.setAmountOut(700); // Less than minimum

//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);

//         mockRouter.setFinalToken(address(tokenB));

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert("Slippage limit exceeded");
//         swapper.swapExactInputMultihop(
//             tokens,
//             poolFees,
//             amountIn,
//             800, // Minimum higher than mock output
//             deadline
//         );
//         vm.stopPrank();
//     }

//     // ============ Exact Output Multihop Tests ============

//     function testSwapExactOutputMultihop_ERC20ToERC20ToERC20_Success() public {
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2000;
//         uint24[] memory poolFees = new uint24[](2);
//         poolFees[0] = 3000; // First hop fee
//         poolFees[1] = 3000; // Second hop fee

//         address[] memory tokens = new address[](3);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);
//         tokens[2] = address(tokenC);

//         // Configure mock router to return tokenC
//         mockRouter.setFinalToken(address(tokenC));

//         uint256 deadline = block.timestamp + 1 hours;
//         uint256 userTokenABalanceBefore = tokenA.balanceOf(user);
//         uint256 userTokenCBalanceBefore = tokenC.balanceOf(user);

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         uint256 amountIn = swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);

//         assertEq(amountIn, mockRouter.mockAmountIn(), "Should get expected amount in");
//         assertLt(amountIn, amountInMaximum, "Should use less than maximum input");
//         assertEq(tokenC.balanceOf(user) - userTokenCBalanceBefore, amountOut, "User should receive tokens");
//         assertLt(tokenA.balanceOf(user), userTokenABalanceBefore, "User should have spent tokens");
//         vm.stopPrank();
//     }

//     function testSwapExactOutputMultihop_ETHToERC20ToERC20_Success() public {
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2 ether;
//         uint24[] memory poolFees = new uint24[](2);
//         poolFees[0] = 3000; // First hop fee
//         poolFees[1] = 3000; // Second hop fee

//         address[] memory tokens = new address[](3);
//         tokens[0] = address(0); // ETH
//         tokens[1] = address(tokenA);
//         tokens[2] = address(tokenB);

//         // Configure mock router to return tokenB
//         mockRouter.setFinalToken(address(tokenB));

//         uint256 deadline = block.timestamp + 1 hours;
//         uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);
//         uint256 userETHBalanceBefore = user.balance;

//         vm.startPrank(user);

//         uint256 amountIn = swapper.swapExactOutputMultihop{value: amountInMaximum}(
//             tokens, poolFees, amountOut, amountInMaximum, deadline
//         );

//         assertEq(amountIn, mockRouter.mockAmountIn(), "Should get expected amount in");
//         assertLt(amountIn, amountInMaximum, "Should use less than maximum input");
//         assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");
//         assertLt(user.balance, userETHBalanceBefore, "User should have spent ETH");
//         vm.stopPrank();
//     }

//     function testSwapExactOutputMultihop_RevertsDeadlinePassed() public {
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2000;
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);

//         uint256 deadline = block.timestamp - 1; // Past deadline

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         vm.expectRevert("Deadline passed");
//         swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);
//         vm.stopPrank();
//     }

//     function testSwapExactOutputMultihop_RevertsInvalidAmounts() public {
//         uint256 amountOut = 0; // Invalid amount
//         uint256 amountInMaximum = 2000;
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         vm.expectRevert("Invalid amounts");
//         swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);
//         vm.stopPrank();
//     }

//     function testSwapExactOutputMultihop_RevertsInsufficientETH() public {
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2 ether;
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(0); // ETH
//         tokens[1] = address(tokenA);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);

//         vm.expectRevert("Insufficient ETH sent");
//         swapper.swapExactOutputMultihop{value: amountInMaximum - 1 ether}(
//             tokens, poolFees, amountOut, amountInMaximum, deadline
//         );
//         vm.stopPrank();
//     }

//     function testSwapExactOutputMultihop_RevertsPairNotAllowed() public {
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2000;
//         uint24[] memory poolFees = new uint24[](2);
//         poolFees[0] = 3000;
//         poolFees[1] = 3000;

//         // Create a new token that's not in the allowlist
//         MockERC20 newToken = new MockERC20("NewToken", "NEW");

//         address[] memory tokens = new address[](3);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);
//         tokens[2] = address(newToken); // tokenB to newToken is not allowed

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         vm.expectRevert("Token pair not allowed");
//         swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);
//         vm.stopPrank();
//     }

//     function testSwapExactOutputMultihop_RevertsWhenPaused() public {
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2000;
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);

//         uint256 deadline = block.timestamp + 1 hours;

//         // Pause the contract
//         vm.prank(admin);
//         swapper.pause();

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         vm.expectRevert("Pausable: paused");
//         swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);
//         vm.stopPrank();
//     }

//     // ============ Path Building Tests ============

//     function testBuildReversedPath_ThreeTokens() public {
//         address[] memory tokens = new address[](3);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);
//         tokens[2] = address(tokenC);

//         uint24[] memory poolFees = new uint24[](2);
//         poolFees[0] = 3000;
//         poolFees[1] = 5000;

//         // Test the _buildReversedPath function indirectly through exactOutput
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2000;
//         uint256 deadline = block.timestamp + 1 hours;

//         // Configure mock router
//         mockRouter.setFinalToken(address(tokenC));

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         uint256 amountIn = swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);

//         assertGt(amountIn, 0, "Should have consumed some input");
//         vm.stopPrank();
//     }

//     function testBuildReversedPath_WithETH() public {
//         address[] memory tokens = new address[](3);
//         tokens[0] = address(0); // ETH
//         tokens[1] = address(tokenA);
//         tokens[2] = address(tokenB);

//         uint24[] memory poolFees = new uint24[](2);
//         poolFees[0] = 3000;
//         poolFees[1] = 5000;

//         // Configure mock router
//         mockRouter.setFinalToken(address(tokenB));

//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2 ether;
//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);

//         uint256 amountIn = swapper.swapExactOutputMultihop{value: amountInMaximum}(
//             tokens, poolFees, amountOut, amountInMaximum, deadline
//         );

//         assertGt(amountIn, 0, "Should have consumed some input");
//         vm.stopPrank();
//     }

//     // ============ Additional Test Coverage ============

//     function testSwapExactInput_WithDifferentPoolFees() public {
//         // Test with different valid pool fees
//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = 900;
//         uint256 deadline = block.timestamp + 1 hours;

//         // Test with 0.05% fee
//         mockTWAPProvider.addSupportedPair(address(tokenA), address(tokenB), 500);

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputSingle(
//             address(tokenA), address(tokenB), amountIn, 500, deadline, amountOutMinimum
//         );

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         vm.stopPrank();
//     }

//     function testSwapExactInput_WithHighPoolFee() public {
//         // Test with 1% fee
//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = 900;
//         uint256 deadline = block.timestamp + 1 hours;

//         mockTWAPProvider.addSupportedPair(address(tokenA), address(tokenB), 10000);

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputSingle(
//             address(tokenA), address(tokenB), amountIn, 10000, deadline, amountOutMinimum
//         );

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         vm.stopPrank();
//     }

//     function testSwapExactInput_ETHToETH_Reverts() public {
//         vm.prank(user);
//         vm.expectRevert("tokenIn and tokenOut must differ");
//         swapper.swapExactInputSingle{value: 1 ether}(
//             address(0), address(0), 1 ether, 3000, block.timestamp + 1 hours, 900
//         );
//     }

//     function testSwapExactInput_ZeroDeadlineReverts() public {
//         vm.startPrank(user);
//         tokenA.approve(address(swapper), 1000);

//         vm.expectRevert("Deadline passed");
//         swapper.swapExactInputSingle(address(tokenA), address(tokenB), 1000, 3000, 0, 900);
//         vm.stopPrank();
//     }

//     function testSwapExactOutput_ZeroDeadlineReverts() public {
//         vm.startPrank(user);
//         tokenA.approve(address(swapper), 2000);

//         vm.expectRevert("Deadline passed");
//         swapper.swapExactOutputSingle(address(tokenA), address(tokenB), 1000, 2000, 3000, 0);
//         vm.stopPrank();
//     }

//     function testSwapExactInput_ExactDeadline() public {
//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = 900;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp; // Exact current time

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputSingle(
//             address(tokenA), address(tokenB), amountIn, poolFee, deadline, amountOutMinimum
//         );

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         vm.stopPrank();
//     }

//     function testSwapExactOutput_ExactDeadline() public {
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2000;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp; // Exact current time

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         uint256 amountIn = swapper.swapExactOutputSingle(
//             address(tokenA), address(tokenB), amountOut, amountInMaximum, poolFee, deadline
//         );

//         assertEq(amountIn, mockRouter.mockAmountIn());
//         vm.stopPrank();
//     }

//     function testSwapExactInput_WithMaxUint256Amount() public {
//         uint256 amountIn = type(uint256).max;
//         uint256 amountOutMinimum = 900;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputSingle(
//             address(tokenA), address(tokenB), amountIn, poolFee, deadline, amountOutMinimum
//         );

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         vm.stopPrank();
//     }

//     function testSwapExactOutput_WithMaxUint256Amount() public {
//         uint256 amountOut = type(uint256).max;
//         uint256 amountInMaximum = type(uint256).max;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         uint256 amountIn = swapper.swapExactOutputSingle(
//             address(tokenA), address(tokenB), amountOut, amountInMaximum, poolFee, deadline
//         );

//         assertEq(amountIn, mockRouter.mockAmountIn());
//         vm.stopPrank();
//     }

//     function testSwapExactInput_WithVerySmallAmount() public {
//         uint256 amountIn = 1; // 1 wei
//         uint256 amountOutMinimum = 0;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputSingle(
//             address(tokenA), address(tokenB), amountIn, poolFee, deadline, amountOutMinimum
//         );

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         vm.stopPrank();
//     }

//     function testSwapExactOutput_WithVerySmallAmount() public {
//         uint256 amountOut = 1; // 1 wei
//         uint256 amountInMaximum = 1000;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         uint256 amountIn = swapper.swapExactOutputSingle(
//             address(tokenA), address(tokenB), amountOut, amountInMaximum, poolFee, deadline
//         );

//         assertEq(amountIn, mockRouter.mockAmountIn());
//         vm.stopPrank();
//     }

//     function testMultihop_WithFourTokens() public {
//         // Test multihop with 4 tokens (3 hops)
//         MockERC20 tokenD = new MockERC20("TokenD", "@Token_D@");
//         tokenD.mint(user, INITIAL_TOKEN_SUPPLY);

//         // Set up supported pairs
//         mockTWAPProvider.addSupportedPair(address(tokenC), address(tokenD), 3000);

//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = 600;
//         uint24[] memory poolFees = new uint24[](3);
//         poolFees[0] = 3000; // tokenA -> tokenB
//         poolFees[1] = 3000; // tokenB -> tokenC
//         poolFees[2] = 3000; // tokenC -> tokenD

//         address[] memory tokens = new address[](4);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);
//         tokens[2] = address(tokenC);
//         tokens[3] = address(tokenD);

//         mockRouter.setFinalToken(address(tokenD));

//         uint256 deadline = block.timestamp + 1 hours;
//         uint256 userTokenDBalanceBefore = tokenD.balanceOf(user);

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputMultihop(tokens, poolFees, amountIn, amountOutMinimum, deadline);

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         assertGt(amountOut, amountOutMinimum, "Should meet minimum output");
//         assertEq(tokenD.balanceOf(user) - userTokenDBalanceBefore, amountOut, "User should receive tokens");
//         vm.stopPrank();
//     }

//     function testMultihop_WithMixedFees() public {
//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = 800;
//         uint24[] memory poolFees = new uint24[](2);
//         poolFees[0] = 500;  // 0.05% fee
//         poolFees[1] = 10000; // 1% fee

//         address[] memory tokens = new address[](3);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);
//         tokens[2] = address(tokenC);

//         // Set up mixed fee pairs
//         mockTWAPProvider.addSupportedPair(address(tokenA), address(tokenB), 500);
//         mockTWAPProvider.addSupportedPair(address(tokenB), address(tokenC), 10000);

//         mockRouter.setFinalToken(address(tokenC));

//         uint256 deadline = block.timestamp + 1 hours;
//         uint256 userTokenCBalanceBefore = tokenC.balanceOf(user);

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputMultihop(tokens, poolFees, amountIn, amountOutMinimum, deadline);

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         assertGt(amountOut, amountOutMinimum, "Should meet minimum output");
//         assertEq(tokenC.balanceOf(user) - userTokenCBalanceBefore, amountOut, "User should receive tokens");
//         vm.stopPrank();
//     }

//     function testMultihop_ExactOutputWithMixedFees() public {
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2000;
//         uint24[] memory poolFees = new uint24[](2);
//         poolFees[0] = 500;  // 0.05% fee
//         poolFees[1] = 10000; // 1% fee

//         address[] memory tokens = new address[](3);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);
//         tokens[2] = address(tokenC);

//         // Set up mixed fee pairs
//         mockTWAPProvider.addSupportedPair(address(tokenA), address(tokenB), 500);
//         mockTWAPProvider.addSupportedPair(address(tokenB), address(tokenC), 10000);

//         mockRouter.setFinalToken(address(tokenC));

//         uint256 deadline = block.timestamp + 1 hours;
//         uint256 userTokenABalanceBefore = tokenA.balanceOf(user);
//         uint256 userTokenCBalanceBefore = tokenC.balanceOf(user);

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         uint256 amountIn = swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);

//         assertEq(amountIn, mockRouter.mockAmountIn());
//         assertLt(amountIn, amountInMaximum, "Should use less than maximum input");
//         assertEq(tokenC.balanceOf(user) - userTokenCBalanceBefore, amountOut, "User should receive tokens");
//         assertLt(tokenA.balanceOf(user), userTokenABalanceBefore, "User should have spent tokens");
//         vm.stopPrank();
//     }

//     function testPauseUnpauseCycle() public {
//         // Test multiple pause/unpause cycles
//         for (uint i = 0; i < 3; i++) {
//             vm.prank(admin);
//             swapper.pause();
//             assertTrue(swapper.paused());

//             vm.prank(admin);
//             swapper.unpause();
//             assertFalse(swapper.paused());
//         }
//     }

//     function testRoleManagement_RevokeAndRegrant() public {
//         // Test revoking and regranting roles
//         vm.prank(admin);
//         swapper.grantPauserRole(user);

//         assertTrue(swapper.hasRole(swapper.PAUSER_ROLE(), user));

//         vm.prank(admin);
//         swapper.revokePauserRole(user);

//         assertFalse(swapper.hasRole(swapper.PAUSER_ROLE(), user));

//         vm.prank(admin);
//         swapper.grantPauserRole(user);

//         assertTrue(swapper.hasRole(swapper.PAUSER_ROLE(), user));
//     }

//     function testRoleManagement_AdminCannotRevokeOwnRole() public {
//         // Admin should not be able to revoke their own admin role
//         vm.prank(admin);
//         vm.expectRevert(); // Should revert when trying to revoke own role
//         swapper.revokeRole(swapper.ADMIN_ROLE(), admin);
//     }

//     function testConstructor_ZeroAddressReverts() public {
//         // Test that constructor reverts with zero addresses
//         vm.expectRevert();
//         new UniswapV3Swapper(address(0), address(mockWETH), address(mockTWAPProvider));

//         vm.expectRevert();
//         new UniswapV3Swapper(address(mockRouter), address(0), address(mockTWAPProvider));

//         vm.expectRevert();
//         new UniswapV3Swapper(address(mockRouter), address(mockWETH), address(0));
//     }

//     function testSwapExactInput_WithExactMinimum() public {
//         // Test swap with exact minimum amount out
//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = mockRouter.mockAmountOut(); // Exact minimum
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputSingle(
//             address(tokenA), address(tokenB), amountIn, poolFee, deadline, amountOutMinimum
//         );

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         assertEq(amountOut, amountOutMinimum, "Should get exact minimum");
//         vm.stopPrank();
//     }

//     function testSwapExactOutput_WithExactMaximum() public {
//         // Test swap with exact maximum amount in
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = mockRouter.mockAmountIn(); // Exact maximum
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         uint256 amountIn = swapper.swapExactOutputSingle(
//             address(tokenA), address(tokenB), amountOut, amountInMaximum, poolFee, deadline
//         );

//         assertEq(amountIn, mockRouter.mockAmountIn());
//         assertEq(amountIn, amountInMaximum, "Should use exact maximum");
//         vm.stopPrank();
//     }

//     // ============ Edge Cases and Error Conditions ============

//     function testSwapExactInput_WithZeroMinimum() public {
//         // Test swap with zero minimum amount out
//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = 0;
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputSingle(
//             address(tokenA), address(tokenB), amountIn, poolFee, deadline, amountOutMinimum
//         );

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         assertGt(amountOut, amountOutMinimum, "Should get more than zero");
//         vm.stopPrank();
//     }

//     function testSwapExactInput_WithVeryHighMinimum() public {
//         // Test swap with very high minimum that should cause slippage error
//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = mockRouter.mockAmountOut() + 1000; // Higher than possible
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert("Slippage limit exceeded");
//         swapper.swapExactInputSingle(
//             address(tokenA), address(tokenB), amountIn, poolFee, deadline, amountOutMinimum
//         );
//         vm.stopPrank();
//     }

//     function testSwapExactOutput_WithVeryLowMaximum() public {
//         // Test swap with very low maximum that should cause insufficient input error
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = mockRouter.mockAmountIn() - 1000; // Lower than needed
//         uint24 poolFee = 3000;
//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         vm.expectRevert("Slippage limit exceeded");
//         swapper.swapExactOutputSingle(
//             address(tokenA), address(tokenB), amountOut, amountInMaximum, poolFee, deadline
//         );
//         vm.stopPrank();
//     }

//     function testMultihop_WithSingleToken() public {
//         // Test multihop with only one token (should revert)
//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](0);
//         address[] memory tokens = new address[](1);
//         tokens[0] = address(tokenA);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert("At least 2 tokens required");
//         swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
//         vm.stopPrank();
//     }

//     function testMultihop_WithMismatchedFees() public {
//         // Test multihop with mismatched fees array length
//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](1); // Only 1 fee for 2 hops
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](3);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);
//         tokens[2] = address(tokenC);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert("Pool fees length must match hops");
//         swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
//         vm.stopPrank();
//     }

//     function testMultihop_WithEmptyFeesArray() public {
//         // Test multihop with empty fees array
//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](0);

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert("Pool fees length must match hops");
//         swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
//         vm.stopPrank();
//     }

//     function testMultihop_WithEmptyTokensArray() public {
//         // Test multihop with empty tokens array
//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](0);
//         address[] memory tokens = new address[](0);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert("At least 2 tokens required");
//         swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
//         vm.stopPrank();
//     }

//     function testSwapExactInput_WithMaxDeadline() public {
//         // Test swap with maximum deadline value
//         uint256 amountIn = 1000;
//         uint256 amountOutMinimum = 900;
//         uint24 poolFee = 3000;
//         uint256 deadline = type(uint256).max;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         uint256 amountOut = swapper.swapExactInputSingle(
//             address(tokenA), address(tokenB), amountIn, poolFee, deadline, amountOutMinimum
//         );

//         assertEq(amountOut, mockRouter.mockAmountOut());
//         vm.stopPrank();
//     }

//     function testSwapExactOutput_WithMaxDeadline() public {
//         // Test swap with maximum deadline value
//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2000;
//         uint24 poolFee = 3000;
//         uint256 deadline = type(uint256).max;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         uint256 amountIn = swapper.swapExactOutputSingle(
//             address(tokenA), address(tokenB), amountOut, amountInMaximum, poolFee, deadline
//         );

//         assertEq(amountIn, mockRouter.mockAmountIn());
//         vm.stopPrank();
//     }

//     function testRoleManagement_GrantRoleToZeroAddress() public {
//         // Test granting role to zero address
//         vm.prank(admin);
//         vm.expectRevert("Zero address not allowed");
//         swapper.grantPauserRole(address(0));
//     }

//     function testRoleManagement_RevokeRoleFromZeroAddress() public {
//         // Test revoking role from zero address
//         vm.prank(admin);
//         vm.expectRevert("Zero address not allowed");
//         swapper.revokePauserRole(address(0));
//     }

//     function testRoleManagement_NonAdminGrantRole() public {
//         // Test non-admin granting role
//         vm.prank(user);
//         vm.expectRevert("Caller is not admin");
//         swapper.grantPauserRole(pauser);
//     }

//     function testRoleManagement_NonAdminRevokeRole() public {
//         // Test non-admin revoking role
//         vm.prank(user);
//         vm.expectRevert("Caller is not admin");
//         swapper.revokePauserRole(pauser);
//     }

//     function testPause_NonPauser() public {
//         // Test non-pauser trying to pause
//         vm.prank(user);
//         vm.expectRevert("Caller is not pauser");
//         swapper.pause();
//     }

//     function testUnpause_NonPauser() public {
//         // Test non-pauser trying to unpause
//         vm.prank(admin);
//         swapper.pause(); // First pause as admin

//         vm.prank(user);
//         vm.expectRevert("Caller is not pauser");
//         swapper.unpause();
//     }

//     function testSwapExactInput_WhenPaused() public {
//         // Test swap when contract is paused
//         vm.prank(admin);
//         swapper.pause();

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), 1000);

//         vm.expectRevert("Pausable: paused");
//         swapper.swapExactInputSingle(address(tokenA), address(tokenB), 1000, 3000, block.timestamp + 1 hours, 900);
//         vm.stopPrank();
//     }

//     function testSwapExactOutput_WhenPaused() public {
//         // Test swap when contract is paused
//         vm.prank(admin);
//         swapper.pause();

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), 2000);

//         vm.expectRevert("Pausable: paused");
//         swapper.swapExactOutputSingle(address(tokenA), address(tokenB), 1000, 2000, 3000, block.timestamp + 1 hours);
//         vm.stopPrank();
//     }

//     function testMultihop_WhenPaused() public {
//         // Test multihop when contract is paused
//         vm.prank(admin);
//         swapper.pause();

//         uint256 amountIn = 1000;
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountIn);

//         vm.expectRevert("Pausable: paused");
//         swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
//         vm.stopPrank();
//     }

//     function testMultihop_ExactOutputWhenPaused() public {
//         // Test multihop exact output when contract is paused
//         vm.prank(admin);
//         swapper.pause();

//         uint256 amountOut = 1000;
//         uint256 amountInMaximum = 2000;
//         uint24[] memory poolFees = new uint24[](1);
//         poolFees[0] = 3000;

//         address[] memory tokens = new address[](2);
//         tokens[0] = address(tokenA);
//         tokens[1] = address(tokenB);

//         uint256 deadline = block.timestamp + 1 hours;

//         vm.startPrank(user);
//         tokenA.approve(address(swapper), amountInMaximum);

//         vm.expectRevert("Pausable: paused");
//         swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);
//         vm.stopPrank();
//     }
// }

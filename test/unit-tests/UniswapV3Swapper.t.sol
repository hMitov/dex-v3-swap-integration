// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../../src/UniswapV3Swapper.sol";
import "../../src/mocks/MockWETH.sol";
import "../../src/mocks/MockSwapRouter.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/mocks/MockUniswapV3Pool.sol"; // Added for callback tests

contract UniswapV3SwapperTest is Test {
    UniswapV3Swapper private swapper;
    MockSwapRouter private mockRouter;
    MockWETH private mockWETH;
    MockERC20 private tokenA;
    MockERC20 private tokenB;
    MockERC20 private tokenC; // Added for multihop tests

    address private admin;
    address private user;
    address private pauser;

    uint256 private constant INITIAL_TOKEN_SUPPLY = 1000 ether;

    function setUp() public {
        admin = makeAddr("ADMIN");
        user = makeAddr("USER");
        pauser = makeAddr("PAUSER");

        vm.startPrank(admin);

        mockRouter = new MockSwapRouter();
        mockWETH = new MockWETH();
        tokenA = new MockERC20("TokenA", "@Token_A@");
        tokenB = new MockERC20("TokenB", "@Token_B@");
        tokenC = new MockERC20("TokenC", "@Token_C@"); // Initialize tokenC

        swapper = new UniswapV3Swapper(address(mockRouter), address(mockWETH), );

        vm.stopPrank();

        tokenA.mint(user, INITIAL_TOKEN_SUPPLY);
        tokenB.mint(user, INITIAL_TOKEN_SUPPLY);
        tokenC.mint(user, INITIAL_TOKEN_SUPPLY); // Mint tokenC for multihop tests

        vm.deal(user, 100 ether);
        vm.deal(pauser, 10 ether);
        vm.deal(address(swapper), 1000 ether);
    }

    function testConstructorArguments() public view {
        assertEq(address(swapper.router()), address(mockRouter));
        assertEq(address(swapper.wETH()), address(mockWETH));
    }

    function testRolesAfterConstructor() public view {
        assertTrue(swapper.hasRole(swapper.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(swapper.hasRole(swapper.ADMIN_ROLE(), admin));
        assertTrue(swapper.hasRole(swapper.PAUSER_ROLE(), admin));
    }

    function testPause() public {
        vm.prank(admin);
        swapper.grantPauserRole(pauser);

        vm.prank(pauser);
        swapper.pause();

        assertTrue(swapper.paused());
    }

    function testUnpause() public {
        vm.prank(admin);
        swapper.pause();

        vm.prank(admin);
        swapper.unpause();

        assertFalse(swapper.paused());
    }

    function testUnpause_RevertsNotPauser() public {
        vm.prank(admin);
        swapper.pause();

        vm.prank(user);
        vm.expectRevert("Caller is not pauser");
        swapper.unpause();
    }

    function testGrantPauserRole() public {
        vm.prank(admin);
        swapper.grantPauserRole(user);

        assertTrue(swapper.hasRole(swapper.PAUSER_ROLE(), user));
    }

    function testGrantPauserRole_RevertsNotAdmin() public {
        vm.prank(user);
        vm.expectRevert("Caller is not admin");
        swapper.grantPauserRole(user);
    }

    function testGrantPauserRole_RevertsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Zero address not allowed");
        swapper.grantPauserRole(address(0));
    }

    function test_RevokePauserRole_OnlyAdminCanCall() public {
        vm.prank(user);
        vm.expectRevert("Caller is not admin");
        swapper.revokePauserRole(user);
    }

    function testRevokePauserRole() public {
        vm.prank(admin);
        swapper.grantPauserRole(user);

        vm.prank(admin);
        swapper.revokePauserRole(user);

        assertFalse(swapper.hasRole(swapper.PAUSER_ROLE(), user));
    }

    function testRevokePauserRole_RevertsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Zero address not allowed");
        swapper.revokePauserRole(address(0));
    }

    function testSwapExactInput_WithERCTokens_Success() public {
        uint256 amountIn = 1000;
        uint256 amountOutMinimum = 900;
        uint24 poolFee = 3000;
        uint256 deadline = block.timestamp + 1 hours;

        // Record initial balances
        uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountIn);

        uint256 amountOut = swapper.swapExactInputSingle(
            address(tokenA), address(tokenB), amountIn, poolFee, deadline, amountOutMinimum
        );

        // Verify swap result
        assertEq(amountOut, mockRouter.mockAmountOut());
        assertGe(amountOut, amountOutMinimum);

        // Verify user received tokens
        assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");

        vm.stopPrank();
    }

    function testSwapExactInput_WithETHToERC20_Success() public {
        uint256 amountIn = 1 ether;
        uint256 amountOutMinimum = 900;
        uint24 poolFee = 3000;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);

        vm.prank(user);
        uint256 amountOut = swapper.swapExactInputSingle{value: amountIn}(
            address(0), address(tokenB), amountIn, poolFee, deadline, amountOutMinimum
        );

        assertEq(amountOut, mockRouter.mockAmountOut());
        assertGe(amountOut, amountOutMinimum);
        assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");
    }

    function testSwapExactInput_WithERC20ToETH_Success() public {
        uint256 amountIn = 1000;
        uint256 amountOutMinimum = 900;
        uint24 poolFee = 3000;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userETHBalanceBefore = user.balance;

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountIn);

        uint256 amountOut =
            swapper.swapExactInputSingle(address(tokenA), address(0), amountIn, poolFee, deadline, amountOutMinimum);

        assertEq(amountOut, mockRouter.mockAmountOut());
        assertGe(amountOut, amountOutMinimum);
        assertEq(user.balance - userETHBalanceBefore, amountOut, "User should receive ETH");

        vm.stopPrank();
    }

    function testSwapExactInput_SameTokenReverts() public {
        vm.prank(user);
        vm.expectRevert("tokenIn and tokenOut must differ");
        swapper.swapExactInputSingle(address(tokenA), address(tokenA), 1000, 3000, block.timestamp + 1 hours, 900);
    }

    function testSwapExactInput_ZeroAmountInReverts() public {
        vm.prank(user);
        vm.expectRevert("amountIn must be greater than zero");
        swapper.swapExactInputSingle(address(tokenA), address(tokenB), 0, 3000, block.timestamp + 1 hours, 900);
    }

    function testSwapExactInput_InvalidPoolFeeReverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid pool fee");
        swapper.swapExactInputSingle(
            address(tokenA),
            address(tokenB),
            1000,
            2000, // Invalid fee
            block.timestamp + 1 hours,
            900
        );
    }

    function testSwapExactInput_DeadlinePassedReverts() public {
        vm.prank(user);
        vm.expectRevert("Deadline passed");
        swapper.swapExactInputSingle(
            address(tokenA),
            address(tokenB),
            1000,
            3000,
            block.timestamp - 1, // Past deadline
            900
        );
    }

    function testSwapExactInput_ETHAmountMismatchReverts() public {
        vm.prank(user);
        vm.expectRevert("ETH amount mismatch");
        swapper.swapExactInputSingle{value: 0.5 ether}(
            address(0),
            address(tokenB),
            1 ether, // Different amount
            3000,
            block.timestamp + 1 hours,
            900
        );
    }

    function testSwapExactInput_ETHNotExpectedReverts() public {
        vm.prank(user);
        vm.expectRevert("ETH not expected");
        swapper.swapExactInputSingle{value: 1 ether}(
            address(tokenA), address(tokenB), 1000, 3000, block.timestamp + 1 hours, 900
        );
    }

    function testSwapExactInput_SlippageExceededReverts() public {
        mockRouter.setAmountOut(800); // Less than minimum

        vm.startPrank(user);
        tokenA.approve(address(swapper), 1000);

        vm.expectRevert("Slippage limit exceeded");
        swapper.swapExactInputSingle(address(tokenA), address(tokenB), 1000, 3000, block.timestamp + 1 hours, 900);
        vm.stopPrank();
    }

    function testSwapExactInput_WhenPausedReverts() public {
        vm.prank(admin);
        swapper.pause();

        vm.startPrank(user);
        tokenA.approve(address(swapper), 1000);

        vm.expectRevert();
        swapper.swapExactInputSingle(address(tokenA), address(tokenB), 1000, 3000, block.timestamp + 1 hours, 900);
        vm.stopPrank();
    }

    // // ============ SwapExactOutputSingle Tests ============

    function testSwapExactOutput_ERC20ToERC20_Success() public {
        uint256 amountOut = 1000;
        uint256 amountInMaximum = 2000;
        uint24 poolFee = 3000;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountInMaximum);

        uint256 amountIn = swapper.swapExactOutputSingle(
            address(tokenA), address(tokenB), amountOut, amountInMaximum, poolFee, deadline
        );

        assertEq(amountIn, mockRouter.mockAmountIn());
        assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
        assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");

        vm.stopPrank();
    }

    function testSwapExactOutput_ETHToERC20_Success() public {
        uint256 amountOut = 1000;
        uint256 amountInMaximum = 2 ether;
        uint24 poolFee = 3000;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);

        vm.prank(user);
        uint256 amountIn = swapper.swapExactOutputSingle{value: amountInMaximum}(
            address(0), address(tokenB), amountOut, amountInMaximum, poolFee, deadline
        );

        assertEq(amountIn, mockRouter.mockAmountIn());
        assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
        assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");
    }

    function testSwapExactOutput_ERC20ToETH_Success() public {
        uint256 amountOut = 1 ether;
        uint256 amountInMaximum = 2000;
        uint24 poolFee = 3000;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userETHBalanceBefore = user.balance;

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountInMaximum);

        uint256 amountIn =
            swapper.swapExactOutputSingle(address(tokenA), address(0), amountOut, amountInMaximum, poolFee, deadline);

        assertEq(amountIn, mockRouter.mockAmountIn());
        assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
        assertEq(user.balance - userETHBalanceBefore, amountOut, "User should receive ETH");
        vm.stopPrank();
    }

    function testSwapExactOutput_SameTokenReverts() public {
        vm.prank(user);
        vm.expectRevert("tokenIn and tokenOut must differ");
        swapper.swapExactOutputSingle(address(tokenA), address(tokenA), 1000, 2000, 3000, block.timestamp + 1 hours);
    }

    function testSwapExactOutput_DeadlinePassedReverts() public {
        vm.prank(user);
        vm.expectRevert("Deadline passed");
        swapper.swapExactOutputSingle(address(tokenA), address(tokenB), 1000, 2000, 3000, block.timestamp - 1);
    }

    function testSwapExactOutput_InvalidAmountsReverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid amounts");
        swapper.swapExactOutputSingle(
            address(tokenA),
            address(tokenB),
            0, // Invalid amountOut
            2000,
            3000,
            block.timestamp + 1 hours
        );
    }

    function testSwapExactOutput_InvalidPoolFeeReverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid pool fee");
        swapper.swapExactOutputSingle(
            address(tokenA),
            address(tokenB),
            1000,
            2000,
            2000, // Invalid fee
            block.timestamp + 1 hours
        );
    }

    function testSwapExactOutput_InsufficientETHReverts() public {
        vm.prank(user);
        vm.expectRevert("Insufficient ETH sent");
        swapper.swapExactOutputSingle{value: 1 ether}(
            address(0),
            address(tokenB),
            1000,
            2 ether, // More than sent
            3000,
            block.timestamp + 1 hours
        );
    }

    function testSwapExactOutput_ETHNotExpectedReverts() public {
        vm.prank(user);
        vm.expectRevert("ETH not expected");
        swapper.swapExactOutputSingle{value: 1 ether}(
            address(tokenA), address(tokenB), 1000, 2000, 3000, block.timestamp + 1 hours
        );
    }

    function testSwapExactOutput_WhenPausedReverts() public {
        vm.prank(admin);
        swapper.pause();

        vm.startPrank(user);
        tokenA.approve(address(swapper), 2000);

        vm.expectRevert();
        swapper.swapExactOutputSingle(address(tokenA), address(tokenB), 1000, 2000, 3000, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    // ============ Allowlist Tests ============

    // function testAllowPair_Success() public {
    //     MockERC20 newToken = new MockERC20("NewToken", "NEW");

    //     vm.prank(admin);
    //     swapper.allowPair(address(tokenA), address(newToken));

    //     assertTrue(swapper.allowedPairs(address(tokenA), address(newToken)), "Pair should be allowed");
    // }

    function testAllowPair_RevertsNotAdmin() public {
        MockERC20 newToken = new MockERC20("NewToken", "NEW");

        vm.prank(user);
        vm.expectRevert("Caller is not admin");
        swapper.allowPair(address(tokenA), address(newToken));
    }

    function testAllowPair_RevertsZeroAddress() public view {
        // Test that ETH pairs can be allowed (they're already allowed in setUp)
        assertTrue(swapper.allowedPairs(address(0), address(tokenA)), "ETH to tokenA pair should be allowed");
        assertTrue(swapper.allowedPairs(address(tokenA), address(0)), "tokenA to ETH pair should be allowed");
    }

    function testAllowPair_RevertsSameToken() public {
        vm.prank(admin);
        vm.expectRevert("Tokens must differ");
        swapper.allowPair(address(tokenA), address(tokenA));
    }

    function testAllowPair_RevertsAlreadyAllowed() public {
        vm.prank(admin);
        vm.expectRevert("Pair already allowed");
        swapper.allowPair(address(tokenA), address(tokenB)); // Already allowed in setUp
    }

    function testRevokePair_Success() public {
        vm.prank(admin);
        swapper.revokePair(address(tokenA), address(tokenB));

        assertFalse(swapper.allowedPairs(address(tokenA), address(tokenB)), "Pair should be revoked");
    }

    function testRevokePair_RevertsNotAdmin() public {
        vm.prank(user);
        vm.expectRevert("Caller is not admin");
        swapper.revokePair(address(tokenA), address(tokenB));
    }

    function testRevokePair_RevertsZeroAddress() public {
        // Test that ETH pairs can be revoked (they're already allowed in setUp)
        vm.prank(admin);
        swapper.revokePair(address(0), address(tokenA));

        assertFalse(swapper.allowedPairs(address(0), address(tokenA)), "ETH to tokenA pair should be revoked");

        // Re-allow it for other tests
        vm.prank(admin);
        swapper.allowPair(address(0), address(tokenA));
    }

    function testRevokePair_RevertsSameToken() public {
        vm.prank(admin);
        vm.expectRevert("Tokens must differ");
        swapper.revokePair(address(tokenA), address(tokenA));
    }

    function testRevokePair_RevertsNotAllowed() public {
        MockERC20 newToken = new MockERC20("NewToken", "NEW");

        vm.prank(admin);
        vm.expectRevert("Pair not allowed");
        swapper.revokePair(address(tokenA), address(newToken)); // Not allowed
    }

    // ============ Swap with Allowlist Tests ============

    function testSwapExactInput_RevertsPairNotAllowed() public {
        MockERC20 newToken = new MockERC20("NewToken", "NEW");

        vm.startPrank(user);
        tokenA.approve(address(swapper), 1000);

        vm.expectRevert("Token pair not allowed");
        swapper.swapExactInputSingle(address(tokenA), address(newToken), 1000, 3000, block.timestamp + 1 hours, 900);
        vm.stopPrank();
    }

    function testSwapExactOutput_RevertsPairNotAllowed() public {
        MockERC20 newToken = new MockERC20("NewToken", "NEW");

        vm.startPrank(user);
        tokenA.approve(address(swapper), 2000);

        vm.expectRevert("Token pair not allowed");
        swapper.swapExactOutputSingle(address(tokenA), address(newToken), 1000, 2000, 3000, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function testSwapExactInput_WorksAfterAllowPair() public {
        // Create a new mock token instead of using makeAddr
        MockERC20 newToken = new MockERC20("NewToken", "NEW");
        newToken.mint(address(mockRouter), 10000); // Give some tokens to the router

        // Allow the pair
        vm.prank(admin);
        swapper.allowPair(address(tokenA), address(newToken));

        // Now swap should work
        vm.startPrank(user);
        tokenA.approve(address(swapper), 1000);

        uint256 amountOut =
            swapper.swapExactInputSingle(address(tokenA), address(newToken), 1000, 3000, block.timestamp + 1 hours, 900);

        assertEq(amountOut, mockRouter.mockAmountOut(), "Should get expected amount out");
        vm.stopPrank();
    }

    function testSwapExactInput_RevertsAfterRevokePair() public {
        // Revoke the pair
        vm.prank(admin);
        swapper.revokePair(address(tokenA), address(tokenB));

        // Now swap should fail
        vm.startPrank(user);
        tokenA.approve(address(swapper), 1000);

        vm.expectRevert("Token pair not allowed");
        swapper.swapExactInputSingle(address(tokenA), address(tokenB), 1000, 3000, block.timestamp + 1 hours, 900);
        vm.stopPrank();
    }

    function testAllowPair_EmitsEvent() public {
        MockERC20 newToken = new MockERC20("NewToken", "NEW");

        vm.prank(admin);
        swapper.allowPair(address(tokenA), address(newToken));
    }

    function testRevokePair_EmitsEvent() public {
        vm.prank(admin);
        swapper.revokePair(address(tokenA), address(tokenB));
    }

    // ============ Multihop Tests ============

    function testSwapExactInputMultihop_ERC20ToERC20ToERC20_Success() public {
        uint256 amountIn = 1000;
        uint256 amountOutMinimum = 800;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000; // First hop fee
        poolFees[1] = 3000; // Second hop fee

        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(tokenC);

        mockRouter.setFinalToken(address(tokenC));

        uint256 deadline = block.timestamp + 1 hours;
        uint256 userTokenCBalanceBefore = tokenC.balanceOf(user);

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountIn);

        uint256 amountOut = swapper.swapExactInputMultihop(tokens, poolFees, amountIn, amountOutMinimum, deadline);

        assertEq(amountOut, mockRouter.mockAmountOut(), "Should get expected amount out");
        assertGt(amountOut, amountOutMinimum, "Should meet minimum output");
        assertEq(tokenC.balanceOf(user) - userTokenCBalanceBefore, amountOut, "User should receive tokens");
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_ETHToERC20ToERC20_Success() public {
        uint256 amountIn = 1 ether;
        uint256 amountOutMinimum = 800;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000; // First hop fee
        poolFees[1] = 3000; // Second hop fee

        address[] memory tokens = new address[](3);
        tokens[0] = address(0); // ETH
        tokens[1] = address(tokenA);
        tokens[2] = address(tokenB);

        // Configure mock router to return tokenB
        mockRouter.setFinalToken(address(tokenB));

        uint256 deadline = block.timestamp + 1 hours;
        uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);
        uint256 userETHBalanceBefore = user.balance;

        vm.startPrank(user);

        uint256 amountOut =
            swapper.swapExactInputMultihop{value: amountIn}(tokens, poolFees, amountIn, amountOutMinimum, deadline);

        assertEq(amountOut, mockRouter.mockAmountOut(), "Should get expected amount out");
        assertGt(amountOut, amountOutMinimum, "Should meet minimum output");
        assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");
        assertLt(user.balance, userETHBalanceBefore, "User should have spent ETH");
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_RevertsInsufficientTokens() public {
        uint256 amountIn = 1000;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountIn - 1); // Insufficient approval

        vm.expectRevert();
        swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_RevertsPairNotAllowed() public {
        uint256 amountIn = 1000;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        // Create a new token that's not in the allowlist
        MockERC20 newToken = new MockERC20("NewToken", "NEW");

        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(newToken); // tokenB to newToken is not allowed

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountIn);

        vm.expectRevert("Token pair not allowed");
        swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_RevertsInvalidPathLength() public {
        uint256 amountIn = 1000;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](1); // Only 1 token
        tokens[0] = address(tokenA);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountIn);

        vm.expectRevert("At least 2 tokens required");
        swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_RevertsInvalidFeesLength() public {
        uint256 amountIn = 1000;
        uint24[] memory poolFees = new uint24[](1); // Only 1 fee for 2 hops
        poolFees[0] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(tokenC);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountIn);

        vm.expectRevert("Pool fees length must match hops");
        swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_RevertsZeroAmountIn() public {
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);
        tokenA.approve(address(swapper), 1000);

        vm.expectRevert("amountIn must be greater than zero");
        swapper.swapExactInputMultihop(
            tokens,
            poolFees,
            0, // Zero amount
            800,
            deadline
        );
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_RevertsDeadlinePassed() public {
        uint256 amountIn = 1000;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256 deadline = block.timestamp - 1; // Past deadline

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountIn);

        vm.expectRevert("Deadline passed");
        swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_RevertsWhenPaused() public {
        vm.prank(admin);
        swapper.pause();

        uint256 amountIn = 1000;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountIn);

        vm.expectRevert();
        swapper.swapExactInputMultihop(tokens, poolFees, amountIn, 800, deadline);
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_RevertsSlippageExceeded() public {
        mockRouter.setAmountOut(700); // Less than minimum

        uint256 amountIn = 1000;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        mockRouter.setFinalToken(address(tokenB));

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountIn);

        vm.expectRevert("Slippage limit exceeded");
        swapper.swapExactInputMultihop(
            tokens,
            poolFees,
            amountIn,
            800, // Minimum higher than mock output
            deadline
        );
        vm.stopPrank();
    }

    // ============ Exact Output Multihop Tests ============

    function testSwapExactOutputMultihop_ERC20ToERC20ToERC20_Success() public {
        uint256 amountOut = 1000;
        uint256 amountInMaximum = 2000;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000; // First hop fee
        poolFees[1] = 3000; // Second hop fee

        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(tokenC);

        // Configure mock router to return tokenC
        mockRouter.setFinalToken(address(tokenC));

        uint256 deadline = block.timestamp + 1 hours;
        uint256 userTokenABalanceBefore = tokenA.balanceOf(user);
        uint256 userTokenCBalanceBefore = tokenC.balanceOf(user);

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountInMaximum);

        uint256 amountIn = swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);

        assertEq(amountIn, mockRouter.mockAmountIn(), "Should get expected amount in");
        assertLt(amountIn, amountInMaximum, "Should use less than maximum input");
        assertEq(tokenC.balanceOf(user) - userTokenCBalanceBefore, amountOut, "User should receive tokens");
        assertLt(tokenA.balanceOf(user), userTokenABalanceBefore, "User should have spent tokens");
        vm.stopPrank();
    }

    function testSwapExactOutputMultihop_ETHToERC20ToERC20_Success() public {
        uint256 amountOut = 1000;
        uint256 amountInMaximum = 2 ether;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000; // First hop fee
        poolFees[1] = 3000; // Second hop fee

        address[] memory tokens = new address[](3);
        tokens[0] = address(0); // ETH
        tokens[1] = address(tokenA);
        tokens[2] = address(tokenB);

        // Configure mock router to return tokenB
        mockRouter.setFinalToken(address(tokenB));

        uint256 deadline = block.timestamp + 1 hours;
        uint256 userTokenBBalanceBefore = tokenB.balanceOf(user);
        uint256 userETHBalanceBefore = user.balance;

        vm.startPrank(user);

        uint256 amountIn = swapper.swapExactOutputMultihop{value: amountInMaximum}(
            tokens, poolFees, amountOut, amountInMaximum, deadline
        );

        assertEq(amountIn, mockRouter.mockAmountIn(), "Should get expected amount in");
        assertLt(amountIn, amountInMaximum, "Should use less than maximum input");
        assertEq(tokenB.balanceOf(user) - userTokenBBalanceBefore, amountOut, "User should receive tokens");
        assertLt(user.balance, userETHBalanceBefore, "User should have spent ETH");
        vm.stopPrank();
    }

    function testSwapExactOutputMultihop_RevertsDeadlinePassed() public {
        uint256 amountOut = 1000;
        uint256 amountInMaximum = 2000;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256 deadline = block.timestamp - 1; // Past deadline

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountInMaximum);

        vm.expectRevert("Deadline passed");
        swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);
        vm.stopPrank();
    }

    function testSwapExactOutputMultihop_RevertsInvalidAmounts() public {
        uint256 amountOut = 0; // Invalid amount
        uint256 amountInMaximum = 2000;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountInMaximum);

        vm.expectRevert("Invalid amounts");
        swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);
        vm.stopPrank();
    }

    function testSwapExactOutputMultihop_RevertsInsufficientETH() public {
        uint256 amountOut = 1000;
        uint256 amountInMaximum = 2 ether;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(0); // ETH
        tokens[1] = address(tokenA);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);

        vm.expectRevert("Insufficient ETH sent");
        swapper.swapExactOutputMultihop{value: amountInMaximum - 1 ether}(
            tokens, poolFees, amountOut, amountInMaximum, deadline
        );
        vm.stopPrank();
    }

    function testSwapExactOutputMultihop_RevertsPairNotAllowed() public {
        uint256 amountOut = 1000;
        uint256 amountInMaximum = 2000;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        // Create a new token that's not in the allowlist
        MockERC20 newToken = new MockERC20("NewToken", "NEW");

        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(newToken); // tokenB to newToken is not allowed

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountInMaximum);

        vm.expectRevert("Token pair not allowed");
        swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);
        vm.stopPrank();
    }

    function testSwapExactOutputMultihop_RevertsWhenPaused() public {
        uint256 amountOut = 1000;
        uint256 amountInMaximum = 2000;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        uint256 deadline = block.timestamp + 1 hours;

        // Pause the contract
        vm.prank(admin);
        swapper.pause();

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountInMaximum);

        vm.expectRevert("Pausable: paused");
        swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);
        vm.stopPrank();
    }

    // ============ Path Building Tests ============

    function testBuildReversedPath_ThreeTokens() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(tokenC);

        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 5000;

        // Test the _buildReversedPath function indirectly through exactOutput
        uint256 amountOut = 1000;
        uint256 amountInMaximum = 2000;
        uint256 deadline = block.timestamp + 1 hours;

        // Configure mock router
        mockRouter.setFinalToken(address(tokenC));

        vm.startPrank(user);
        tokenA.approve(address(swapper), amountInMaximum);

        uint256 amountIn = swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);

        assertGt(amountIn, 0, "Should have consumed some input");
        vm.stopPrank();
    }

    function testBuildReversedPath_WithETH() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(0); // ETH
        tokens[1] = address(tokenA);
        tokens[2] = address(tokenB);

        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 5000;

        // Configure mock router
        mockRouter.setFinalToken(address(tokenB));

        uint256 amountOut = 1000;
        uint256 amountInMaximum = 2 ether;
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);

        uint256 amountIn = swapper.swapExactOutputMultihop{value: amountInMaximum}(
            tokens, poolFees, amountOut, amountInMaximum, deadline
        );

        assertGt(amountIn, 0, "Should have consumed some input");
        vm.stopPrank();
    }
}

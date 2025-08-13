// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../../src/UniswapV3Swapper.sol";
import "../../src/TWAPPriceProvider.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @title UniswapV3Swapper Integration Tests
/// @notice Integration tests for UniswapV3Swapper contract using mainnet fork
contract UniswapV3SwapperITTest is Test {
    // ============ CONTRACT INSTANCES ============
    UniswapV3Swapper private swapper;
    TWAPPriceProvider private twapProvider;
    IUniswapV3Factory private factory;

    // ============ TEST ACCOUNTS ============
    address private user;
    address private admin;

    // ============ MAINNET ADDRESSES ============
    address private constant MAINNET_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant FACTORY_ADDRESS = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    // Token interfaces
    IERC20 private weth;
    IERC20 private usdc;
    IERC20 private usdt;
    uint24 private poolFee = 3000;

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

        // Deploy swapper contract
        vm.startPrank(admin);
        twapProvider = new TWAPPriceProvider();
        swapper = new UniswapV3Swapper(MAINNET_ROUTER, MAINNET_WETH, address(twapProvider));

        console.log("Integration contract deployed at:", address(swapper));
        console.log("Using Mainnet Router:", MAINNET_ROUTER);
        console.log("Using Mainnet WETH:", MAINNET_WETH);
        console.log("User address:", user);
        console.log("Admin address:", admin);
        console.log("User ETH balance:", user.balance);
        console.log("Admin ETH balance:", admin.balance);
        console.log("Fork block:", vm.getBlockNumber());

        factory = IUniswapV3Factory(FACTORY_ADDRESS);

        // Add token pairs with correct pool token order
        _addTokenPairWithCorrectOrder(address(weth), address(usdc), poolFee); // ETH to USDC
        _addTokenPairWithCorrectOrder(address(weth), address(usdt), poolFee); // ETH to USDT
        _addTokenPairWithCorrectOrder(address(usdc), address(usdt), poolFee); // USDC to USDT
        vm.stopPrank();
    }

    // ============ SETUP & CONFIGURATION TESTS ============

    function testSetup() public view {
        assertEq(address(swapper) != address(0), true, "Integration contract should be deployed");
        assertEq(user.balance, 100 ether, "User should have 100 ETH");
        assertEq(admin.balance, 50 ether, "Admin should have 50 ETH");
        assertEq(address(weth), MAINNET_WETH, "WETH should be initialized");
        assertEq(address(usdc), MAINNET_USDC, "USDC should be initialized");
    }

    // ============ EXACT INPUT SINGLE-HOP INTEGRATION TESTS ============

    function testSwapExactInput_WETHToUSDC_IT_SUCCESS() public {
        uint256 amountIn = 0.01 ether;
        uint256 amountOutMinimum = 0;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userUSDCBalanceBefore = usdc.balanceOf(user);
        uint256 userETHBalanceBefore = user.balance;

        vm.startPrank(user);

        uint256 amountOut = swapper.swapExactInputSingle{value: amountIn}(
            address(0), // ETH
            address(usdc),
            amountIn,
            poolFee,
            deadline,
            amountOutMinimum
        );

        vm.stopPrank();

        // Verify the swap worked
        assertGt(amountOut, 0, "Should receive some USDC");
        assertGt(usdc.balanceOf(user), userUSDCBalanceBefore, "User should have received USDC");
        assertLt(user.balance, userETHBalanceBefore, "User should have spent ETH");

        console.log("SUCCESS: WETH to USDC swap");
        console.log("Amount in (WETH):", amountIn);
        console.log("Amount out (USDC):", amountOut);
        console.log("User USDC balance after:", usdc.balanceOf(user));
        console.log("User ETH balance after:", user.balance);
    }

    function testSwapExactInput_WETHToUSDT_IT_SUCCESS() public {
        uint256 amountIn = 0.01 ether;
        uint256 amountOutMinimum = 0;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userUSDTBalanceBefore = usdt.balanceOf(user);
        uint256 userETHBalanceBefore = user.balance;

        vm.startPrank(user);

        uint256 amountOut = swapper.swapExactInputSingle{value: amountIn}(
            address(0), // ETH
            address(usdt),
            amountIn,
            poolFee,
            deadline,
            amountOutMinimum
        );

        vm.stopPrank();

        assertGt(amountOut, 0, "Should receive some USDT");
        assertGt(usdt.balanceOf(user), userUSDTBalanceBefore, "User should have received USDT");
        assertLt(user.balance, userETHBalanceBefore, "User should have spent ETH");

        console.log("SUCCESS: WETH to USDT swap");
        console.log("Amount in (WETH):", amountIn);
        console.log("Amount out (USDT):", amountOut);
        console.log("User USDT balance after:", usdt.balanceOf(user));
        console.log("User ETH balance after:", user.balance);
    }

    function testSwapExactInput_USDCToWETH_IT_SUCCESS() public {
        // First, get some USDC by swapping WETH (this is just to have USDC to test with)
        uint256 ethAmount = 0.1 ether;
        uint256 usdcAmount = _swapWETHForUSDC(ethAmount);

        uint256 amountOutMinimum = 0;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userETHBalanceBefore = user.balance;
        uint256 userUSDCBalanceBefore = usdc.balanceOf(user);

        vm.startPrank(user);

        // Approve swapper contract to spend USDC
        usdc.approve(address(swapper), usdcAmount);

        uint256 amountOut = swapper.swapExactInputSingle(
            address(usdc),
            address(0), // ETH
            usdcAmount,
            poolFee,
            deadline,
            amountOutMinimum
        );

        vm.stopPrank();

        assertGt(amountOut, 0, "Should receive some ETH");
        assertGt(user.balance, userETHBalanceBefore, "User should have received ETH");
        assertLt(usdc.balanceOf(user), userUSDCBalanceBefore, "User should have spent USDC");

        console.log("SUCCESS: USDC to WETH swap");
        console.log("Amount in (USDC):", usdcAmount);
        console.log("Amount out (ETH):", amountOut);
        console.log("User ETH balance after:", user.balance);
    }

    // ============ EXACT OUTPUT SINGLE-HOP INTEGRATION TESTS ============

    function testSwapExactOutputSingle_WETHToUSDC_IT_SUCCESS() public {
        uint256 amountOut = 50 * 10 ** 6;
        uint256 amountInMaximum = 0.05 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 userUSDCBalanceBefore = usdc.balanceOf(user);
        uint256 userETHBalanceBefore = user.balance;

        vm.startPrank(user);

        uint256 amountIn = swapper.swapExactOutputSingle{value: amountInMaximum}(
            address(0), // WETH
            address(usdc),
            amountOut,
            amountInMaximum,
            poolFee,
            deadline
        );

        vm.stopPrank();

        assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
        assertGt(amountIn, 0, "Should have spent some ETH");
        assertEq(usdc.balanceOf(user) - userUSDCBalanceBefore, amountOut, "Should receive exact USDC amount");
        assertLt(user.balance, userETHBalanceBefore, "User should have spent ETH");

        console.log("SUCCESS: WETH to USDC exact output single hop");
        console.log("Amount out (USDC):", amountOut);
        console.log("Amount in (WETH):", amountIn);
        console.log("Amount in maximum (WETH):", amountInMaximum);
        console.log("User USDC balance after:", usdc.balanceOf(user));
        console.log("User ETH balance after:", user.balance);
    }

    function testSwapExactOutput_WETHToUSDC_IT_SUCCESS() public {
        uint256 amountOut = 100 * 10 ** 6;
        uint256 amountInMaximum = 0.1 ether;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userUSDCBalanceBefore = usdc.balanceOf(user);

        vm.startPrank(user);

        uint256 amountIn = swapper.swapExactOutputSingle{value: amountInMaximum}(
            address(0), // ETH
            address(usdc),
            amountOut,
            amountInMaximum,
            poolFee,
            deadline
        );

        vm.stopPrank();

        assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
        assertGt(amountIn, 0, "Should have spent some ETH");
        assertEq(usdc.balanceOf(user) - userUSDCBalanceBefore, amountOut, "Should receive exact amount");

        console.log("SUCCESS: WETH to USDC exact output");
        console.log("Amount out (USDC):", amountOut);
        console.log("Amount in (ETH):", amountIn);
        console.log("User USDC balance after:", usdc.balanceOf(user));
    }

    function testSwapExactOutput_USDCToWETH_IT_SUCCESS() public {
        // First, get some USDC by swapping WETH
        uint256 ethAmount = 0.1 ether;
        uint256 usdcAmount = _swapWETHForUSDC(ethAmount);

        uint256 amountOut = 0.01 ether; // 0.01 ETH
        uint256 amountInMaximum = usdcAmount; // Use all USDC we have
        uint256 deadline = block.timestamp + 1 hours;

        uint256 userETHBalanceBefore = user.balance;

        vm.startPrank(user);

        // Approve swapper contract to spend USDC
        usdc.approve(address(swapper), amountInMaximum);

        uint256 amountIn = swapper.swapExactOutputSingle(
            address(usdc),
            address(0), // ETH
            amountOut,
            amountInMaximum,
            poolFee,
            deadline
        );

        vm.stopPrank();

        assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
        assertGt(amountIn, 0, "Should have spent some USDC");
        assertEq(user.balance - userETHBalanceBefore, amountOut, "Should receive exact ETH amount");

        console.log("SUCCESS: USDC to WETH exact output");
        console.log("Amount out (ETH):", amountOut);
        console.log("Amount in (USDC):", amountIn);
        console.log("User ETH balance after:", user.balance);
        console.log("User USDC balance after:", usdc.balanceOf(user));
    }

    // ============ EXACT INPUT MULTIHOP INTEGRATION TESTS ============

    function testSwapExactInputMultihop_WETHToUSDCToUSDT_IT_SUCCESS() public {
        uint256 amountIn = 0.1 ether;
        uint256 amountOutMinimum = 100; // Minimum 100 USDT
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000; // WETH to USDC (0.3%)
        poolFees[1] = 3000; // USDC to USDT (0.3%)

        address[] memory tokens = new address[](3);
        tokens[0] = address(0); // WETH
        tokens[1] = MAINNET_USDC;
        tokens[2] = MAINNET_USDT;

        uint256 deadline = block.timestamp + 1 hours;
        uint256 userUSDTBalanceBefore = usdt.balanceOf(user);

        vm.startPrank(user);

        uint256 amountOut =
            swapper.swapExactInputMultihop{value: amountIn}(tokens, poolFees, amountIn, amountOutMinimum, deadline);

        assertGt(amountOut, amountOutMinimum, "Should meet minimum output");
        assertEq(usdt.balanceOf(user) - userUSDTBalanceBefore, amountOut, "User should receive USDT");
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_USDCToWETHToUSDT_IT_SUCCESS() public {
        uint256 wethAmount = 0.1 ether;
        uint256 usdcReceived = _swapWETHForUSDC(wethAmount);

        uint256 amountIn = usdcReceived;
        uint256 amountOutMinimum = 0;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = MAINNET_USDC;
        tokens[1] = address(0); // WETH
        tokens[2] = MAINNET_USDT;

        uint256 deadline = block.timestamp + 1 hours;
        uint256 userUSDTBalanceBefore = usdt.balanceOf(user);

        vm.startPrank(user);
        usdc.approve(address(swapper), amountIn);

        uint256 amountOut = swapper.swapExactInputMultihop(tokens, poolFees, amountIn, amountOutMinimum, deadline);

        assertGt(amountOut, amountOutMinimum, "Should meet minimum output");
        assertGt(usdt.balanceOf(user) - userUSDTBalanceBefore, 0, "User should receive USDT");
        vm.stopPrank();
    }

    // ============ REVERT & ERROR TESTS ============

    function testSwapExactInputMultihop_RevertsPairNotAllowed() public {
        uint256 amountIn = 0.1 ether;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = address(0); // WETH
        tokens[1] = MAINNET_USDC;
        tokens[2] = MAINNET_USDT;

        vm.prank(admin);
        twapProvider.removeTokenPair(MAINNET_USDC, MAINNET_USDT, 3000);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);

        vm.expectRevert("Token pair not allowed");
        swapper.swapExactInputMultihop{value: amountIn}(tokens, poolFees, amountIn, 100, deadline);
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_RevertsInvalidPathLength() public {
        uint256 amountIn = 0.1 ether;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);

        vm.expectRevert("At least 2 tokens required");
        swapper.swapExactInputMultihop{value: amountIn}(tokens, poolFees, amountIn, 100, deadline);
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_RevertsInvalidFeesLength() public {
        uint256 amountIn = 0.1 ether;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = address(0);
        tokens[1] = MAINNET_USDC;
        tokens[2] = MAINNET_USDT;

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);

        vm.expectRevert("Pool fees length must match hops");
        swapper.swapExactInputMultihop{value: amountIn}(tokens, poolFees, amountIn, 100, deadline);
        vm.stopPrank();
    }

    function testSwapExactInputMultihop_RevertsDeadlinePassed() public {
        uint256 amountIn = 0.1 ether;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = address(0);
        tokens[1] = MAINNET_USDC;
        tokens[2] = MAINNET_USDT;

        uint256 deadline = block.timestamp - 1;

        vm.startPrank(user);

        vm.expectRevert("Deadline passed");
        swapper.swapExactInputMultihop{value: amountIn}(tokens, poolFees, amountIn, 100, deadline);
        vm.stopPrank();
    }

    // // ============ Exact Output Multihop Success Tests ============

    function testSwapExactOutputMultihop_WETHToUSDCToUSDT_IT_SUCCESS() public {
        uint256 amountOut = 50 * 10 ** 6;
        uint256 amountInMaximum = 0.1 ether;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = address(0); // WETH
        tokens[1] = MAINNET_USDC;
        tokens[2] = MAINNET_USDT;

        uint256 deadline = block.timestamp + 1 hours;
        uint256 userUSDTBalanceBefore = usdt.balanceOf(user);
        uint256 userETHBalanceBefore = user.balance;

        vm.startPrank(user);

        uint256 amountIn = swapper.swapExactOutputMultihop{value: amountInMaximum}(
            tokens, poolFees, amountOut, amountInMaximum, deadline
        );

        vm.stopPrank();

        // Verify the swap worked correctly
        assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
        assertGt(amountIn, 0, "Should have spent some ETH");
        assertEq(usdt.balanceOf(user) - userUSDTBalanceBefore, amountOut, "Should receive exact USDT amount");
        assertLt(user.balance, userETHBalanceBefore, "User should have spent ETH");

        console.log("SUCCESS: WETH to USDC to USDT exact output multihop");
        console.log("Amount out (USDT):", amountOut);
        console.log("Amount in (ETH):", amountIn);
        console.log("Amount in maximum (ETH):", amountInMaximum);
        console.log("User USDT balance after:", usdt.balanceOf(user));
        console.log("User ETH balance after:", user.balance);
        console.log("ETH refund:", userETHBalanceBefore - user.balance - amountIn);
    }

    function testSwapExactOutputMultihop_USDCToWETHToUSDT_IT_SUCCESS() public {
        uint256 ethAmount = 0.1 ether;
        uint256 usdcAmount = _swapWETHForUSDC(ethAmount);

        uint256 amountOut = 50 * 10 ** 6;
        uint256 amountInMaximum = 0;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = MAINNET_USDC;
        tokens[1] = address(0); // WETH
        tokens[2] = MAINNET_USDT;

        uint256 deadline = block.timestamp + 1 hours;
        uint256 userUSDCBalanceBefore = usdc.balanceOf(user);
        uint256 userUSDTBalanceBefore = usdt.balanceOf(user);

        vm.startPrank(user);

        usdc.approve(address(swapper), usdcAmount);
        uint256 amountIn = swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);

        vm.stopPrank();

        // Verify the swap worked correctly
        assertLe(amountIn, usdcAmount, "Amount in should not exceed what we have");
        assertGt(amountIn, 0, "Should have spent some USDC");
        assertEq(usdt.balanceOf(user) - userUSDTBalanceBefore, amountOut, "Should receive exact USDT amount");
        assertLt(usdc.balanceOf(user), userUSDCBalanceBefore, "User should have spent USDC");

        console.log("SUCCESS: USDC to WETH to USDT exact output multihop with TWAP logic");
        console.log("Amount out (USDT):", amountOut);
        console.log("Amount in (USDC):", amountIn);
        console.log("Amount in maximum (USDC):", amountInMaximum);
        console.log("User USDC balance after:", usdc.balanceOf(user));
        console.log("User USDT balance after:", usdt.balanceOf(user));
        console.log("USDC refund:", userUSDCBalanceBefore - usdc.balanceOf(user) - amountIn);
    }

    function testSwapExactOutputMultihop_WETHToUSDTToUSDC_IT_SUCCESS() public {
        uint256 amountOut = 100 * 10 ** 6;
        uint256 amountInMaximum = 0.1 ether;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = address(0);
        tokens[1] = MAINNET_USDT;
        tokens[2] = MAINNET_USDC;

        uint256 deadline = block.timestamp + 1 hours;
        uint256 userUSDCBalanceBefore = usdc.balanceOf(user);
        uint256 userETHBalanceBefore = user.balance;

        vm.startPrank(user);

        uint256 amountIn = swapper.swapExactOutputMultihop{value: amountInMaximum}(
            tokens, poolFees, amountOut, amountInMaximum, deadline
        );

        vm.stopPrank();

        assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
        assertGt(amountIn, 0, "Should have spent some ETH");
        assertEq(usdc.balanceOf(user) - userUSDCBalanceBefore, amountOut, "Should receive exact USDC amount");
        assertLt(user.balance, userETHBalanceBefore, "User should have spent ETH");

        console.log("SUCCESS: WETH to USDT to USDC exact output multihop");
        console.log("Amount out (USDC):", amountOut);
        console.log("Amount in (ETH):", amountIn);
        console.log("Amount in maximum (ETH):", amountInMaximum);
        console.log("User USDC balance after:", usdc.balanceOf(user));
        console.log("User ETH balance after:", user.balance);
        console.log("ETH refund:", userETHBalanceBefore - user.balance - amountIn);
    }

    function testSwapExactOutputMultihop_WETHToUSDC_IT_SUCCESS() public {
        uint256 amountOut = 50 * 10 ** 6;
        uint256 amountInMaximum = 0.05 ether;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(0);
        tokens[1] = MAINNET_USDC;

        uint256 deadline = block.timestamp + 1 hours;
        uint256 userUSDCBalanceBefore = usdc.balanceOf(user);
        uint256 userETHBalanceBefore = user.balance;

        vm.startPrank(user);

        uint256 amountIn = swapper.swapExactOutputMultihop{value: amountInMaximum}(
            tokens, poolFees, amountOut, amountInMaximum, deadline
        );

        vm.stopPrank();

        assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
        assertGt(amountIn, 0, "Should have spent some ETH");
        assertEq(usdc.balanceOf(user) - userUSDCBalanceBefore, amountOut, "Should receive exact USDC amount");
        assertLt(user.balance, userETHBalanceBefore, "User should have spent ETH");

        console.log("SUCCESS: WETH to USDC exact output multihop (single hop)");
        console.log("Amount out (USDC):", amountOut);
        console.log("Amount in (ETH):", amountIn);
        console.log("Amount in maximum (ETH):", amountInMaximum);
        console.log("User USDC balance after:", usdc.balanceOf(user));
        console.log("User ETH balance after:", user.balance);
        console.log("ETH refund:", userETHBalanceBefore - user.balance - amountIn);
    }

    function testSwapExactOutputMultihop_USDCToWETH_IT_SUCCESS() public {
        uint256 ethAmount = 0.1 ether;
        uint256 usdcAmount = _swapWETHForUSDC(ethAmount);

        uint256 amountOut = 0.02 ether;
        uint256 amountInMaximum = usdcAmount;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](2);
        tokens[0] = MAINNET_USDC;
        tokens[1] = address(0);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 userETHBalanceBefore = user.balance;
        uint256 userUSDCBalanceBefore = usdc.balanceOf(user);

        vm.startPrank(user);

        usdc.approve(address(swapper), amountInMaximum);

        uint256 amountIn = swapper.swapExactOutputMultihop(tokens, poolFees, amountOut, amountInMaximum, deadline);

        vm.stopPrank();

        assertLe(amountIn, amountInMaximum, "Amount in should not exceed maximum");
        assertGt(amountIn, 0, "Should have spent some USDC");
        assertEq(user.balance - userETHBalanceBefore, amountOut, "Should receive exact ETH amount");
        assertLt(usdc.balanceOf(user), userUSDCBalanceBefore, "User should have spent USDC");

        console.log("SUCCESS: USDC to WETH exact output multihop (single hop)");
        console.log("Amount out (ETH):", amountOut);
        console.log("Amount in (USDC):", amountIn);
        console.log("Amount in maximum (USDC):", amountInMaximum);
        console.log("User ETH balance after:", user.balance);
        console.log("User USDC balance after:", usdc.balanceOf(user));
        console.log("USDC refund:", userUSDCBalanceBefore - usdc.balanceOf(user) - amountIn);
    }

    function testSwapExactOutputMultihop_RevertsPairNotAllowed() public {
        uint256 amountOut = 100 * 10 ** 6;
        uint256 amountInMaximum = 0.2 ether;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = address(0);
        tokens[1] = MAINNET_USDC;
        tokens[2] = MAINNET_USDT;

        vm.prank(admin);
        twapProvider.removeTokenPair(MAINNET_USDC, MAINNET_USDT, 3000);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);

        vm.expectRevert("Token pair not allowed");
        swapper.swapExactOutputMultihop{value: amountInMaximum}(tokens, poolFees, amountOut, amountInMaximum, deadline);
        vm.stopPrank();
    }

    function testSwapExactOutputMultihop_RevertsInvalidPathLength() public {
        uint256 amountOut = 100 * 10 ** 6;
        uint256 amountInMaximum = 0.2 ether;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);

        vm.expectRevert("At least 2 tokens required");
        swapper.swapExactOutputMultihop{value: amountInMaximum}(tokens, poolFees, amountOut, amountInMaximum, deadline);
        vm.stopPrank();
    }

    function testSwapExactOutputMultihop_RevertsInvalidFeesLength() public {
        uint256 amountOut = 100 * 10 ** 6;
        uint256 amountInMaximum = 0.2 ether;
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = address(0);
        tokens[1] = MAINNET_USDC;
        tokens[2] = MAINNET_USDT;

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);

        vm.expectRevert("Pool fees length must match hops");
        swapper.swapExactOutputMultihop{value: amountInMaximum}(tokens, poolFees, amountOut, amountInMaximum, deadline);
        vm.stopPrank();
    }

    function testSwapExactOutputMultihop_RevertsDeadlinePassed() public {
        uint256 amountOut = 100 * 10 ** 6;
        uint256 amountInMaximum = 0.2 ether;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = address(0);
        tokens[1] = MAINNET_USDC;
        tokens[2] = MAINNET_USDT;

        uint256 deadline = block.timestamp - 1;

        vm.startPrank(user);

        vm.expectRevert("Deadline passed");
        swapper.swapExactOutputMultihop{value: amountInMaximum}(tokens, poolFees, amountOut, amountInMaximum, deadline);
        vm.stopPrank();
    }

    function testSwapExactOutputMultihop_RevertsWhenPaused() public {
        vm.prank(admin);
        swapper.pause();

        uint256 amountOut = 100 * 10 ** 6;
        uint256 amountInMaximum = 0.2 ether;
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        address[] memory tokens = new address[](3);
        tokens[0] = address(0);
        tokens[1] = MAINNET_USDC;
        tokens[2] = MAINNET_USDT;

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);

        vm.expectRevert();
        swapper.swapExactOutputMultihop{value: amountInMaximum}(tokens, poolFees, amountOut, amountInMaximum, deadline);
        vm.stopPrank();
    }

    // ============ UTILITY & HELPER FUNCTIONS ============

    function _swapWETHForUSDT(uint256 ethAmount) internal returns (uint256) {
        uint256 amountOutMinimum = 0;
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);

        uint256 amountOut = swapper.swapExactInputSingle{value: ethAmount}(
            address(0), address(usdt), ethAmount, poolFee, deadline, amountOutMinimum
        );

        vm.stopPrank();

        return amountOut;
    }

    function _addTokenPairWithCorrectOrder(address tokenA, address tokenB, uint24 fee) internal {
        address poolAddress = factory.getPool(tokenA, tokenB, fee);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        address token0 = pool.token0();
        address token1 = pool.token1();

        if (token0 == tokenA && token1 == tokenB) {
            twapProvider.addTokenPair(tokenA, tokenB, poolAddress, fee);
        } else if (token0 == tokenB && token1 == tokenA) {
            twapProvider.addTokenPair(tokenB, tokenA, poolAddress, fee);
        }
    }

    function _swapWETHForUSDC(uint256 wethAmount) internal returns (uint256) {
        uint256 amountOutMinimum = 0;
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(user);
        uint256 amountOut = swapper.swapExactInputSingle{value: wethAmount}(
            address(0), address(usdc), wethAmount, poolFee, deadline, amountOutMinimum
        );
        vm.stopPrank();

        return amountOut;
    }
}

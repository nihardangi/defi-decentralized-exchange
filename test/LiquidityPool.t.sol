// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DeployLiquidityPool} from "script/DeployLiquidityPool.s.sol";
import {LiquidityPool} from "src/LiquidityPool.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract LiquidityPoolTest is Test {
    DeployLiquidityPool deployer;
    LiquidityPool deployedPool;
    HelperConfig config;
    ERC20Mock token;
    ERC20 lpToken;
    address lp1 = makeAddr("lp1");
    address lp2 = makeAddr("lp2");
    address lp3 = makeAddr("lp3");

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    uint256 constant LP_START_ETH_BALANCE = 10 ether;
    uint256 constant USER_START_ETH_BALANCE = 1 ether;
    uint256 constant LP_START_ERC20_BALANCE = 5000 ether;
    uint256 constant USER_START_ERC20_BALANCE = 200 ether;

    function setUp() external {
        deployer = new DeployLiquidityPool();
        (deployedPool, config) = deployer.deploy();
        (address tokenAddress,) = config.activeNetworkConfig();
        token = ERC20Mock(tokenAddress);
        lpToken = ERC20(deployedPool.getLPTokenAddress());

        // Mint ERC20 tokens for LPs
        token.mint(lp1, LP_START_ERC20_BALANCE);
        token.mint(lp2, LP_START_ERC20_BALANCE);
        token.mint(lp3, LP_START_ERC20_BALANCE);

        // Fund LPs
        vm.deal(lp1, LP_START_ETH_BALANCE);
        vm.deal(lp2, LP_START_ETH_BALANCE);
        vm.deal(lp3, LP_START_ETH_BALANCE);

        vm.deal(user1, USER_START_ETH_BALANCE);
        token.mint(user1, USER_START_ERC20_BALANCE);

        vm.deal(user2, USER_START_ETH_BALANCE);
        token.mint(user2, USER_START_ERC20_BALANCE);
    }

    ////////////////////////////////////
    ///       AddLiquidity Tests    ////
    ////////////////////////////////////
    modifier addFirstLiquidity() {
        uint256 ethToTransfer = 1 ether;
        uint256 maxAmountOfTokens = 2000 ether;
        vm.startPrank(lp1);
        token.approve(address(deployedPool), maxAmountOfTokens);
        deployedPool.addLiquidity{value: ethToTransfer}(maxAmountOfTokens, lp1);
        vm.stopPrank();
        _;
    }

    modifier addSecondLiquidity() {
        uint256 ethToTransfer = 0.5 ether;
        uint256 maxAmountOfTokens = 2500 ether;
        vm.startPrank(lp2);
        token.approve(address(deployedPool), maxAmountOfTokens);
        deployedPool.addLiquidity{value: ethToTransfer}(maxAmountOfTokens, lp2);
        vm.stopPrank();
        _;
    }

    function testRevertsWhenAmountIsZero() external {
        uint256 ethToTransfer = 1 ether;
        uint256 maxAmountOfTokens = 0;
        vm.startPrank(lp1);
        token.approve(address(deployedPool), maxAmountOfTokens);
        vm.expectRevert(LiquidityPool.LiquidityPool__MustBeGreaterThanZero.selector);
        deployedPool.addLiquidity{value: ethToTransfer}(maxAmountOfTokens, lp1);
        vm.stopPrank();
    }

    function testRevertsWhenAmountOfTokensIsLessThanRequired() external addFirstLiquidity {
        uint256 ethToTransfer = 1 ether;
        uint256 maxAmountOfTokens = 1000e18;
        vm.startPrank(lp2);
        token.approve(address(deployedPool), maxAmountOfTokens);
        vm.expectRevert(LiquidityPool.LiquidityPool__LessThanRequiredERC20Tokens.selector);
        deployedPool.addLiquidity{value: ethToTransfer}(maxAmountOfTokens, lp2);
        vm.stopPrank();
    }

    function testOnlyRequiredERC20TokensAreConsumed() external addFirstLiquidity {
        uint256 ethToTransfer = 1 ether;
        uint256 maxAmountOfTokens = 2500e18;
        uint256 poolStartERC20Balance = token.balanceOf(address(deployedPool));
        vm.startPrank(lp2);
        token.approve(address(deployedPool), maxAmountOfTokens);
        // Protocol would only need 2000 tokens for 1 ETH, so it should transfer only 2000 tokens to itself instead of 2500.
        deployedPool.addLiquidity{value: ethToTransfer}(maxAmountOfTokens, lp2);
        vm.stopPrank();

        assert(token.balanceOf(lp2) == LP_START_ERC20_BALANCE - 2000 ether);
        uint256 poolCurrentERC20Balance = token.balanceOf(address(deployedPool));
        assert(poolCurrentERC20Balance == poolStartERC20Balance + 2000 ether);
    }

    function testFirstLiquidityProviderCanAddFunds() external addFirstLiquidity {
        assert(address(deployedPool).balance == 1 ether);
        assert(token.balanceOf(address(deployedPool)) == 2000 ether);
        assert(lpToken.balanceOf(lp1) == 1 ether);
    }

    //////////////////////////////////////
    ///      ethToTokenSwap Tests     ////
    //////////////////////////////////////
    function swapETHForToken(uint256 amountOfETH, address user) private returns (uint256 tokenAmount) {
        vm.prank(user);
        tokenAmount = deployedPool.ethToTokenSwap{value: amountOfETH}(user);
    }

    function testFunctionReturnsCorrectTokenAmountAfterSwappingWithETH()
        external
        addFirstLiquidity
        addSecondLiquidity
    {
        uint256 amountOfETH = 0.1 ether;
        uint256 tokenAmount = swapETHForToken(amountOfETH, user2);
        assert(tokenAmount == 186972557354503969495);
    }

    //////////////////////////////////////
    ///      tokenToEthSwap Tests     ////
    //////////////////////////////////////
    function swapTokensForETH(uint256 tokenAmount, address user) private returns (uint256 ethTransferred) {
        vm.startPrank(user);
        token.approve(address(deployedPool), tokenAmount);
        ethTransferred = deployedPool.tokenToETHSwap(tokenAmount, user);
        vm.stopPrank();
    }

    function testFunctionReturnsCorrectETHAmountAfterSwappingWithERC20()
        external
        addFirstLiquidity
        addSecondLiquidity
    {
        uint256 tokenAmount = 100e18;
        uint256 ethAmount = swapTokensForETH(tokenAmount, user1);
        // console2.log("user1 token balance-------------", ethAmount);
        assert(ethAmount == 48246604510113882);
    }

    function testFunctionReturnsCorrectETHAmountAfterMutipleSwaps() external addFirstLiquidity addSecondLiquidity {
        uint256 tokenAmountForSwap1 = 50e18;
        swapTokensForETH(tokenAmountForSwap1, user1);
        uint256 ethAmountForSwap2 = 0.025 ether;
        uint256 tokenAmount = swapETHForToken(ethAmountForSwap2, user2);
        console2.log("user1 token balance-------------", tokenAmount);

        uint256 tokenAmountForSwap3 = 50e18;
        uint256 ethAmount = swapTokensForETH(tokenAmountForSwap3, user1);
        console2.log("user1 token balance-------------", ethAmount);
        // assert(ethAmount == 186972557354503969495);
    }

    //////////////////////////////////////
    ///     removeLiquidity Tests     ////
    //////////////////////////////////////
    function testFunctionReturnsCorrectStakeBackToLPBeforeAnySwaps() external addFirstLiquidity addSecondLiquidity {
        vm.startPrank(lp1);
        uint256 balance = lpToken.balanceOf(lp1);
        lpToken.approve(address(deployedPool), balance);
        vm.stopPrank();
        deployedPool.removeLiquidity(lp1, lpToken.balanceOf(lp1));
        assert(address(lp1).balance == LP_START_ETH_BALANCE);
        assert(token.balanceOf(lp1) == LP_START_ERC20_BALANCE);
    }

    function testFunctionReturnsCorrectStakeBackToLPAfter2Swaps() external addFirstLiquidity addSecondLiquidity {
        uint256 tokenAmountForSwap1 = 50e18;
        swapTokensForETH(tokenAmountForSwap1, user1);
        uint256 ethAmountForSwap2 = 0.1 ether;
        uint256 tokenAmount = swapETHForToken(ethAmountForSwap2, user2);
        console2.log("user1 token balance-------------", tokenAmount);

        (uint256 ethReserve, uint256 erc20TokenReserve) = deployedPool.getReserves(0);
        console2.log("eth reserve--------", ethReserve);
        console2.log("erc20 reserve------", erc20TokenReserve);
        uint256 lpETHBalanceStart = address(lp1).balance;
        uint256 lpERC20BalanceStart = token.balanceOf(lp1);

        vm.startPrank(lp1);
        uint256 balance = lpToken.balanceOf(lp1);
        lpToken.approve(address(deployedPool), balance);
        vm.stopPrank();
        deployedPool.removeLiquidity(lp1, lpToken.balanceOf(lp1));

        assertEq(address(lp1).balance, lpETHBalanceStart + (2 * ethReserve) / 3);
        assertEq(token.balanceOf(lp1), lpERC20BalanceStart + (2 * erc20TokenReserve) / 3);
    }
}

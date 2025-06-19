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

    uint256 constant LP_START_ETH_BALANCE = 10 ether;
    uint256 constant LP_START_ERC20_BALANCE = 5000 ether;

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
    }

    // function testIfEverythingWorking() external view {
    //     console2.log("address of lp token", deployedPool.getLPTokenAddress());
    //     ERC20 lpToken = ERC20(deployedPool.getLPTokenAddress());

    //     console2.log("name---------", lpToken.name());
    //     console2.log("symbol---------", lpToken.symbol());
    // }

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
        deployedPool.addLiquidity{value: ethToTransfer}(maxAmountOfTokens, lp1);
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
}

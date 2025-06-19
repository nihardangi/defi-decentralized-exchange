// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./LPToken.sol";
import {console2} from "forge-std/console2.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidityPool is ReentrancyGuard {
    /////////////////////////////////////
    ///           Errors              ///
    /////////////////////////////////////
    error LiquidityPool__MustBeGreaterThanZero();
    error LiquidityPool__MintFailed();
    error LiquidityPool__TransferFailed();
    error LiquidityPool__LessThanRequiredERC20Tokens();
    error LiquidityPool__FailedToSendETH();

    ////////////////////////////////////
    ///       State Variables        ///
    ////////////////////////////////////
    uint256 private constant PRECISION = 1e18;
    uint256 private constant SWAP_FEE = 3e15; // 0.3% swap fee
    uint256 private constant SWAP_FEE_PRECISION = 3e18;

    ERC20 immutable i_token;
    LPToken immutable i_LPToken;

    ///////////////////////////////////
    ///         Modifiers           ///
    ///////////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert LiquidityPool__MustBeGreaterThanZero();
        }
        _;
    }

    ///////////////////////////////////
    ///         Functions           ///
    //////////////////////////////////
    constructor(address tokenAddress) {
        i_token = ERC20(tokenAddress);
        string memory tokenSymbol = i_token.symbol();
        // returns name like ETH/DOGE or ETH/WETH
        string memory lpTokenSymbol = string.concat("ETH", tokenSymbol, "LPT");
        string memory lpTokenName = string.concat(tokenSymbol, "/ETH", " LP Token");
        i_LPToken = new LPToken(address(this), lpTokenName, lpTokenSymbol);
    }

    /////////////////////////////////////
    ///  External & Public Functions  ///
    /////////////////////////////////////
    // 1. Check if tokens are in correct amount (using the current pricing of the pool)
    function addLiquidity(uint256 maxAmount, address user)
        external
        payable
        moreThanZero(msg.value)
        moreThanZero(maxAmount)
    {
        console2.log("my ETH Balance is-------", address(this).balance);
        uint256 erc20TokensRequired = _calculateERC20TokensRequired(msg.value);
        if (maxAmount < erc20TokensRequired) {
            revert LiquidityPool__LessThanRequiredERC20Tokens();
        }
        uint256 amountToTransfer = erc20TokensRequired;
        if (erc20TokensRequired == 0) {
            amountToTransfer = maxAmount;
        }
        bool success = i_token.transferFrom(user, address(this), amountToTransfer);
        if (!success) {
            revert LiquidityPool__TransferFailed();
        }
        uint256 lpTokensToMint = _calculateLPTokensToMint(msg.value);
        _mintLPTokens(lpTokensToMint, user);
    }

    function ethToTokenSwap(address user) external payable moreThanZero(msg.value) {
        (uint256 ethReserve, uint256 erc20TokenReserve) = getReserves(msg.value);
        // x * y = k, where x is ETH reserve, y is ERC20 token reserve and k is an invariant that has to remain constant.
        uint256 invariant = ethReserve * erc20TokenReserve;
        // SWAP FEE of 0.3% is removed from ETH deposited by user.
        uint256 ethDepositByUserAfterRemovingSwapFee = msg.value - ((msg.value * SWAP_FEE) / SWAP_FEE_PRECISION);
        // (x+Δx)*(y+Δy)=k, where k is invariant => so (y+Δy) = k/(x+Δx)
        uint256 erc20TokenReserveNewValue = invariant / (ethReserve + ethDepositByUserAfterRemovingSwapFee);
        uint256 tokensToTransfer = erc20TokenReserve - erc20TokenReserveNewValue;
        bool success = i_token.transfer(user, tokensToTransfer);
        if (!success) {
            revert LiquidityPool__TransferFailed();
        }
    }

    function tokenToETHSwap(uint256 amount, address user) external nonReentrant {
        (uint256 ethReserve, uint256 erc20TokenReserve) = getReserves(0);
        // x * y = k, where x is ETH reserve, y is ERC20 token reserve and k is an invariant that has to remain constant
        uint256 invariant = ethReserve * erc20TokenReserve;
        // SWAP FEE of 0.3% is removed from the token amount deposited by user.
        uint256 tokenDepositByUserAfterRemovingSwapFee = amount - ((amount * SWAP_FEE) / SWAP_FEE_PRECISION);
        // (x+Δx)*(y+Δy)=k, where k is invariant => so (x+Δx) = k/(y+Δy)
        uint256 ethReserveNewValue = invariant / (erc20TokenReserve + tokenDepositByUserAfterRemovingSwapFee);
        uint256 ethToTransfer = ethReserve - ethReserveNewValue;

        bool success = i_token.transferFrom(user, address(this), amount);
        if (!success) {
            revert LiquidityPool__TransferFailed();
        }

        (bool sent,) = user.call{value: ethToTransfer}("");
        if (!sent) {
            revert LiquidityPool__FailedToSendETH();
        }
    }

    function removeLiquidity() external {}

    ////////////////////////////////////////
    ///  Private and Internal Functions  ///
    ////////////////////////////////////////
    function _mintLPTokens(uint256 amount, address user) internal moreThanZero(amount) {
        bool minted = i_LPToken.mint(user, amount);
        if (!minted) {
            revert LiquidityPool__MintFailed();
        }
    }

    function _burnLPTokens(uint256 amount) internal moreThanZero(amount) {
        i_LPToken.burn(amount);
    }

    /////////////////////////////////////////////
    ///  Private and Internal View Functions  ///
    /////////////////////////////////////////////
    function _calculateLPTokensToMint(uint256 ethDepositByUser) internal view returns (uint256 newTokensToMint) {
        (uint256 ethReserve,) = getReserves(ethDepositByUser);
        uint256 totalTokensMinted = i_LPToken.totalSupply();
        // First liquidity provider
        if (totalTokensMinted == 0) {
            return ethDepositByUser;
        }
        newTokensToMint = (ethDepositByUser * totalTokensMinted) / ethReserve;
    }

    function _calculateERC20TokensRequired(uint256 ethDepositByUser) internal view returns (uint256) {
        uint256 priceOfTokenPerETH = calculatePriceOfTokenPerETH(ethDepositByUser);
        return (ethDepositByUser * priceOfTokenPerETH) / PRECISION;
    }

    ////////////////////////////////////////////
    ///  Public and External View Functions  ///
    ////////////////////////////////////////////
    // function getName() external view returns (string memory) {
    //     string memory tokenSymbol = ERC20(address(i_token)).symbol();
    //     // returns name like ETH/DOGE or ETH/WETH
    //     return string.concat("ETH/", tokenSymbol);
    // }
    function calculatePriceOfTokenPerETH(uint256 ethDepositByUser) public view returns (uint256) {
        (uint256 ethReserve, uint256 erc20TokenReserve) = getReserves(ethDepositByUser);
        if (erc20TokenReserve == 0) {
            return 0;
        }
        console2.log("price is------------", erc20TokenReserve * PRECISION / ethReserve);
        return erc20TokenReserve * PRECISION / ethReserve;
    }

    function getReserves(uint256 newlyAddedAmount)
        public
        view
        returns (uint256 ethReserve, uint256 erc20TokenReserve)
    {
        ethReserve = address(this).balance - newlyAddedAmount;
        erc20TokenReserve = i_token.balanceOf(address(this));
    }

    function getLPTokenAddress() external view returns (address) {
        return address(i_LPToken);
    }
}

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

contract LiquidityPool {
    /////////////////////////////////////
    ///           Errors              ///
    /////////////////////////////////////
    error LiquidityPool__MustBeGreaterThanZero();
    error LiquidityPool__MintFailed();
    error LiquidityPool__TransferFailed();
    error LiquidityPool__LessThanRequiredERC20Tokens();

    ////////////////////////////////////
    ///       State Variables        ///
    ////////////////////////////////////
    uint256 private constant PRECISION = 1e18;

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

    modifier shouldBeMoreThanOrEqualToRequiredERC20Tokens(uint256 ethDepositByUser, uint256 amount) {
        if (amount < _calculateERC20TokensRequired(ethDepositByUser)) {
            revert LiquidityPool__LessThanRequiredERC20Tokens();
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
        // -----------------------REFACTOR LOGIC HERE------------------
        string memory lpTokenSymbol = string.concat("E", tokenSymbol, "LPT");
        string memory lpTokenName = string.concat(tokenSymbol, "/ETH", " LP Token");
        i_LPToken = new LPToken(address(this), lpTokenName, lpTokenSymbol);
    }

    /////////////////////////////////////
    ///  External & Public Functions  ///
    /////////////////////////////////////
    // 1. Check if tokens are in correct amount (using the current pricing of the pool)
    function addLiquidity(uint256 amount, address user)
        external
        payable
        moreThanZero(amount)
        shouldBeMoreThanOrEqualToRequiredERC20Tokens(msg.value, amount)
    {
        bool success = i_token.transferFrom(user, address(this), amount);
        if (!success) {
            revert LiquidityPool__TransferFailed();
        }
        uint256 lpTokensToMint = _calculateLPTokensToMint(msg.value);
        _mintLPTokens(lpTokensToMint, user);
    }

    function swapTokensForEth() external payable {}

    function swapEthForTokens() external {}

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
        (uint256 ethReserve,) = getReserves();
        uint256 totalTokensMinted = i_LPToken.totalSupply();
        // First liquidity provider
        if (totalTokensMinted == 0) {
            newTokensToMint = ethDepositByUser;
        }
        newTokensToMint = (ethDepositByUser * totalTokensMinted) / ethReserve;
    }

    function _calculateERC20TokensRequired(uint256 ethDepositByUser) internal view returns (uint256) {
        uint256 priceOfTokenPerETH = _calculatePriceOfTokenPerETH();
        return (ethDepositByUser * priceOfTokenPerETH) / PRECISION;
    }

    function _calculatePriceOfTokenPerETH() internal view returns (uint256) {
        uint256 ethReserve = address(this).balance;
        uint256 erc20TokenReserve = i_token.balanceOf(address(this));
        return erc20TokenReserve * PRECISION / ethReserve;
    }

    ////////////////////////////////////////////
    ///  Public and External View Functions  ///
    ////////////////////////////////////////////
    // function getName() external view returns (string memory) {
    //     string memory tokenSymbol = ERC20(address(i_token)).symbol();
    //     // returns name like ETH/DOGE or ETH/WETH
    //     return string.concat("ETH/", tokenSymbol);
    // }

    function getReserves() public view returns (uint256 ethReserve, uint256 erc20TokenReserve) {
        ethReserve = address(this).balance;
        erc20TokenReserve = i_token.balanceOf(address(this));
    }
}

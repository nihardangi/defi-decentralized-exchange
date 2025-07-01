// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./LPToken.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/*
     * @title LiquidityPool
     * @author Nihar Dangi
     *
     * The contract is designed to be as minimal as possible. 
     * It is based on Uniswap v1 model.   
     *      
     * Liquidity pool can be created for every ETH <-> ERC20 token pair.
     * For every liquidity pool, a liquidity provider token is initialized which helps in keeping 
     * track of each liquidity provider's share.
     * Anyone can create a pool and anyone can become a liquidity provider.
     * Protocol charges 0.3% swap fee from users which is added back to the pool.
     * Arbitrage oppotunities ensure that the prices very quickly become equal to the market price after a trade is executed.
     *  
     *
     * @notice This contract creates a liquidity pool for a ETH <-> ERC20 token pair. It handles all the logic for adding and 
     * removing liquidity and ETH <-> ERC20 token swaps.
*/
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
    uint256 private constant SWAP_FEE_PRECISION = 1e18;

    ERC20 immutable i_token;
    LPToken immutable i_LPToken;

    /////////////////////////////////////
    ///           Events              ///
    /////////////////////////////////////
    event AddLiquidity(address indexed liquidityProvider, uint256 indexed ethAmount, uint256 indexed tokenAmount);
    event RemoveLiquidity(address indexed liquidityProvider, uint256 indexed ethAmount, uint256 indexed tokenAmount);
    event ERC20TokenPurchased(address indexed user, uint256 indexed ethSold, uint256 indexed tokensBought);
    event ETHPurchased(address indexed user, uint256 indexed tokensSold, uint256 indexed ethBought);

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
    /*
     * @param maxAmount: Maximum amount of tokens that the user is willing to add to the pool 
     * @notice Adds liquidity to the pool. 
     * @notice Expects user's deposit (in value) to be comprised of 50% ETH and 50% ERC 20 tokens.
     * @notice Checks if tokens are in correct amount (using the current pricing of the pool)
     */
    function addLiquidity(uint256 maxAmount) external payable moreThanZero(msg.value) moreThanZero(maxAmount) {
        address lp = msg.sender;
        uint256 erc20TokensRequired = _calculateERC20TokensRequired(msg.value);
        if (maxAmount < erc20TokensRequired) {
            revert LiquidityPool__LessThanRequiredERC20Tokens();
        }
        uint256 amountToTransfer = erc20TokensRequired;
        if (erc20TokensRequired == 0) {
            amountToTransfer = maxAmount;
        }
        bool success = i_token.transferFrom(lp, address(this), amountToTransfer);
        if (!success) {
            revert LiquidityPool__TransferFailed();
        }
        uint256 lpTokensToMint = _calculateLPTokensToMint(msg.value);
        _mintLPTokens(lpTokensToMint, lp);
        emit AddLiquidity(lp, msg.value, amountToTransfer);
    }

    /*    
     * @notice Swaps ETH for ERC20 tokens. 
     * @notice Uses x * y = k constant product AMM formula to determine the amount of tokens to be transferred to the user.
     */
    function ethToTokenSwap() external payable moreThanZero(msg.value) nonReentrant returns (uint256) {
        address user = msg.sender;
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
        emit ERC20TokenPurchased(user, msg.value, tokensToTransfer);
        return tokensToTransfer;
    }

    /*    
     * @param amount: The amount of ERC20 tokens that user wants to swap for ETH.
     * @notice Swaps ERC20 tokens for ETH. 
     * @notice Uses x * y = k constant product AMM formula to determine the amount of ETH to be transferred to the user.
     */
    function tokenToETHSwap(uint256 amount) external moreThanZero(amount) nonReentrant returns (uint256) {
        address user = msg.sender;
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
        emit ETHPurchased(user, amount, ethToTransfer);
        return ethToTransfer;
    }

    /*    
     * @param amountOfLPTokens: The amount of LP tokens that user wants to liquidate.
     * @notice Calculates the amount of ETH and ERC20 tokens to transfer back to the user based on the amount of LP tokens.
     * @notice Transfers the LP tokens from the user to this contract.
     * @notice Burn the LP tokens
     * @notice Now, transfer the calculated(user's share) ETH and ERC20 tokens to the user.
     */
    function removeLiquidity(uint256 amountOfLPTokens) external moreThanZero(amountOfLPTokens) nonReentrant {
        address lp = msg.sender;
        uint256 totalLPTokensMinted = i_LPToken.totalSupply();
        (uint256 ethReserve, uint256 erc20TokenReserve) = getReserves(0);
        uint256 userETHShare = (amountOfLPTokens * ethReserve) / totalLPTokensMinted;
        uint256 userERC20TokensShare = (amountOfLPTokens * erc20TokenReserve) / totalLPTokensMinted;

        bool success = i_LPToken.transferFrom(lp, address(this), amountOfLPTokens);
        if (!success) {
            revert LiquidityPool__TransferFailed();
        }
        _burnLPTokens(amountOfLPTokens);

        // Send ETH back to liquidity provider
        (bool sent,) = lp.call{value: userETHShare}("");
        if (!sent) {
            revert LiquidityPool__FailedToSendETH();
        }
        // Send ERC20 tokens back to liquidity provider
        bool transferred = i_token.transfer(lp, userERC20TokensShare);
        if (!transferred) {
            revert LiquidityPool__TransferFailed();
        }
        emit RemoveLiquidity(lp, userETHShare, userERC20TokensShare);
    }

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
    function calculatePriceOfTokenPerETH(uint256 ethDepositByUser) public view returns (uint256) {
        (uint256 ethReserve, uint256 erc20TokenReserve) = getReserves(ethDepositByUser);
        if (erc20TokenReserve == 0) {
            return 0;
        }
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

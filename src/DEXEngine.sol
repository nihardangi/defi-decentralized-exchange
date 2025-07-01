// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LiquidityPool} from "./LiquidityPool.sol";

/*
     * @title DEXEngine
     * @author Nihar Dangi     
     *
     * @notice This contract is the core of Decentralized Exchange. It handles all the logic of creating a new 
     * liquidity pool and storing the mappings of liquidity pool <-> ERC20 token.
     * 
*/
contract DEXEngine {
    /////////////////////////////////////
    ///           Errors              ///
    /////////////////////////////////////
    error DEXEngine__LiquidityPoolExistsForToken();

    ////////////////////////////////////
    ///       State Variables        ///
    ////////////////////////////////////
    mapping(address => address) tokenToLiquidityPool;
    mapping(address => address) liquidityPoolToToken;

    /////////////////////////////////////
    ///           Events              ///
    /////////////////////////////////////
    event NewLiquidityPoolCreated(address indexed token, address indexed pool);

    /////////////////////////////////////
    ///  External & Public Functions  ///
    /////////////////////////////////////
    /*
     * @param token: Address of the ERC20 token for which the liquidity pool is being created
     * @notice If liquidity pool for ERC20 token doesn't exist, then it creates a new liquidity pool and adds it to the mapping     
     */
    function createLiquidityPool(address token) external returns (address) {
        if (tokenToLiquidityPool[token] != address(0)) {
            revert DEXEngine__LiquidityPoolExistsForToken();
        }
        LiquidityPool pool = new LiquidityPool(token);
        tokenToLiquidityPool[token] = address(pool);
        liquidityPoolToToken[address(pool)] = token;
        emit NewLiquidityPoolCreated(token, address(pool));
        return address(pool);
    }

    //////////////////////////////////////////
    ///  External & Public View Functions  ///
    //////////////////////////////////////////
    function getLiquidityPool(address token) external view returns (address) {
        return tokenToLiquidityPool[token];
    }

    function getToken(address pool) external view returns (address) {
        return liquidityPoolToToken[pool];
    }
}

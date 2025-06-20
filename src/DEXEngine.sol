// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LiquidityPool} from "./LiquidityPool.sol";

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

    function getLiquidityPool(address token) external view returns (address) {
        return tokenToLiquidityPool[token];
    }

    function getToken(address pool) external view returns (address) {
        return liquidityPoolToToken[pool];
    }
}

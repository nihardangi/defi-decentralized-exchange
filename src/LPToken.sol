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

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LPToken is ERC20Burnable, Ownable {
    error LPToken_MustBeGreaterThanZero();
    error LPToken_BurnAmountExccedsBalance();
    error LPToken_NotZeroAddress();

    constructor(address initialOwner) ERC20("LP Token", "LPT") Ownable(initialOwner) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = address(this).balance;
        if (_amount <= 0) {
            revert LPToken_MustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert LPToken_BurnAmountExccedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert LPToken_NotZeroAddress();
        }
        if (_amount <= 0) {
            revert LPToken_MustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}

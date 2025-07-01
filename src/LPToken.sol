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

/*
     * @title LPToken
     * @author Nihar Dangi     
     *
     * @notice This contract creates an ERC20 burnable token. Owner can mint and burn tokens     
*/
contract LPToken is ERC20Burnable, Ownable {
    error LPToken_MustBeGreaterThanZero();
    error LPToken_BurnAmountExccedsBalance();
    error LPToken_NotZeroAddress();

    constructor(address initialOwner, string memory name, string memory symbol)
        ERC20(name, symbol)
        Ownable(initialOwner)
    {}

    /*
     * @param _amount: Amount of tokens to burn
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert LPToken_MustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert LPToken_BurnAmountExccedsBalance();
        }
        super.burn(_amount);
    }

    /*
     * @param _to: Address of the receiver of newly minted tokens
     * @param _amount: Amount of tokens to mint
     */
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

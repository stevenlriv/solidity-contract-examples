//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./SpaceLib.sol";
import "./SpaceICO.sol";

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SpaceCoin is ERC20 {
    bool public shouldTax;

    address public ico;
    address public owner;
    address public treasury;

    constructor(address _treasury) ERC20("Space", "SPC") {
        owner = msg.sender;
        treasury = _treasury;

        ico = address(new SpaceICO(owner, this, _treasury));

        uint256 icoAmount = SpaceLib.ONE_COIN * 30000 * 5; // 5:1 ratio for 30k ether
        _mint(ico, icoAmount);
        _mint(_treasury, SpaceLib.MAX_COINS - icoAmount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        // Don't do this!
        // require(amount > 0, "ZERO_AMOUNT");

        if (shouldTax) {
            // In general: multiply values before dividing values when doing math, to avoid losing precision.
            // In general: Check your number upper bound (to prevent overflow) before increasing values.
            // In this case: You can avoid increasing altogether and just divide by 50.
            uint256 taxAmount = (amount * 2) / 100;
            super._transfer(sender, treasury, taxAmount);
        }
        super._transfer(sender, recipient, amount);
    }

    function toggleTax(bool _shouldTax) external {
        if (msg.sender != owner) revert NotOwner();

        shouldTax = _shouldTax;
    }

    error NotOwner();
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC20 } from "../lib/solmate/src/tokens/ERC20.sol";
import { Owned } from "../lib/solmate/src/auth/Owned.sol";

contract ERC20Test is ERC20, Owned {
    constructor() ERC20("ERC20Test", "MTC", 18) Owned(msg.sender) {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        require(msg.sender == from, "UNAUTHORIZED");
        _burn(from, amount);
    }
}

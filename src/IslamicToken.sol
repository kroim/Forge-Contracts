// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../custom-lib/Auth.sol";

contract IslamicToken is ERC20, Auth {
    using Address for address;

    string private _name = "Islamic Token ";
    string private _symbol = "ISLT";
    uint256 private _initialSupply = 1_000_000_000;

    constructor() ERC20(_name, _symbol) Auth(msg.sender) {
        _mint(msg.sender, _initialSupply * (10 ** decimals()));
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address _to, uint256 _amount) public authorized {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) public authorized {
        _burn(_msgSender(), _amount);
    }
}
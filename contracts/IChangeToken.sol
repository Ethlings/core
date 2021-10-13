// SPDX-License-Identifier: MIT

pragma solidity >= 0.6.0;

import "./lib/IERC20.sol";

interface IChangeToken is IERC20 {
    function mintOnAvatarCreation(address recipient, uint256 numberOfAvatars) external;
    function burn(address sender, uint256 amount) external;
}

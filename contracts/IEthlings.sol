// SPDX-License-Identifier: MIT

pragma solidity >= 0.6.0;

import "./lib/IERC721.sol";

interface IEthlings is IERC721 {
    function avatarExists(uint256 avatarId) external view returns (bool);
}
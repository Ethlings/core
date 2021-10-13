// SPDX-License-Identifier: MIT

pragma solidity >= 0.6.0;

interface IWearables {
    function getCurrentPrintPrice(uint256 originalId) external view returns (uint256 printPrice_);
    function getCurrentBurnPrice(uint256 originalId) external view returns (uint256 burnPrice_);
    function getReserve() external view returns (uint256 reserveTotal_);

    function _print(address sender, uint256 originalId, uint256 availableFunds) external returns (uint256 printPrice_);
    function _burnPrint(address sender, uint256 originalId) external returns (uint256 burnPrice_);
    function _escrow(address owner, uint256 originalId) external;
    function _redeem(address owner, uint256 originalId) external;
    function _releaseBondingCurve(address owner, uint256 originalId) external returns (uint256 releaseAmount_);
}
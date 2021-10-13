// SPDX-License-Identifier: MIT

pragma solidity >= 0.6.0;

import "./IChangeToken.sol";
import "./lib/SafeERC20.sol";
import "./lib/IERC1155.sol";
import "./IEthlings.sol";
import "./lib/ReentrancyGuard.sol";
import "./lib/ERC20.sol";
import "./lib/Ownable.sol";

contract ChangeToken is IChangeToken, ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Constants
    uint256 public constant SECONDS_IN_A_YEAR = 86400 * 365;
    uint256 public constant INITIAL_ALLOTMENT = 1000 * (10 ** 18);
    uint256 public constant EMISSION_PER_YEAR = 1000 * (10 ** 18);
    uint256 public constant OWNER_EMISSION_PER_YEAR = (10 ** 7 - (7777 * 1000)) * 10 ** 18;

    // Public variables
    uint256 public emissionStart;
    uint256 public emissionEnd; 
    
    uint256 private _ownerLastClaim;
    uint32[7777] private _lastClaims;
    //mapping(uint256 => uint256) private _lastClaim;

    address private _ethlingsAddress;

    event EthlingsAddressSet(address ethlingsAddress);
    
    constructor(uint256 initialSupply) ERC20("Ethlings Token", "ET") public {
        _mint(msg.sender, initialSupply);
        emissionStart = block.timestamp;
        emissionEnd = emissionStart + SECONDS_IN_A_YEAR;
        _ownerLastClaim = block.timestamp;
    }
    
    function setEthlingsAddress(address ethlingsAddress) public onlyOwner {
        require(_ethlingsAddress == address(0), "Cannot change Ethlings address");
        _ethlingsAddress = ethlingsAddress;
        emit EthlingsAddressSet(ethlingsAddress);
    }

    function lastClaim(uint256 avatarId) public view returns (uint256) {
        uint256 index = (avatarId >> 224) & 0x3FFF;
        uint256 lastClaimed = _lastClaims[index] != 0 ? _lastClaims[index] : emissionStart;
        return lastClaimed;
    }

    function batchAccumulated(uint256[] memory avatarIds) external view returns (uint256) {
        uint256 total = 0;
        for (uint i = 0; i < avatarIds.length; i++) {
            total = total.add(accumulated(avatarIds[i]));
        }
        return total;
    }

    function accumulated(uint256 avatarId) public view returns (uint256) {
        require(block.timestamp > emissionStart, "Emission has not started yet");
        require(IEthlings(_ethlingsAddress).avatarExists(avatarId), "Avatar does not exist");

        uint256 lastClaimed = lastClaim(avatarId);

        // Sanity check if last claim was on or after emission end
        if (lastClaimed >= emissionEnd) return 0;

        uint256 currentTime = block.timestamp < emissionEnd ? block.timestamp : emissionEnd; // Getting the min value of both
        uint256 totalAccumulated = currentTime.sub(lastClaimed).mul(EMISSION_PER_YEAR).div(SECONDS_IN_A_YEAR);

        return totalAccumulated;
    }

    function claim(uint256[] memory avatarIds) public nonReentrant returns (uint256) {
        require(block.timestamp > emissionStart, "Emission has not started yet");

        uint256 avatarId;
        uint256 totalClaimQty = 0;
        uint256 index;
        for (uint i = 0; i < avatarIds.length; i++) {
            // Sanity check for non-minted index
            require(IEthlings(_ethlingsAddress).avatarExists(avatarIds[i]), "Avatar does not exist");

            avatarId = avatarIds[i];
            require(IEthlings(_ethlingsAddress).ownerOf(avatarId) == msg.sender, "Sender is not the owner");

            uint256 claimQty = accumulated(avatarId);
            if (claimQty != 0) {
                totalClaimQty = totalClaimQty.add(claimQty);
                index = (avatarId >> 224) & 0x3FFF;
                _lastClaims[index] = uint32(block.timestamp < emissionEnd ? block.timestamp : emissionEnd);
            }
        }

        require(totalClaimQty != 0, "No accumulated tokens");
        _mint(msg.sender, totalClaimQty); 
        return totalClaimQty;
    }

    function ownerClaim() public onlyOwner {
        uint256 currentTime = block.timestamp < emissionEnd ? block.timestamp : emissionEnd; // Getting the min value of both
        uint256 totalAccumulated = currentTime.sub(_ownerLastClaim).mul(OWNER_EMISSION_PER_YEAR).div(SECONDS_IN_A_YEAR);

        require(totalAccumulated != 0, "No accumulated tokens");
        _ownerLastClaim = block.timestamp;
        _mint(msg.sender, totalAccumulated);
    }

    function mintOnAvatarCreation(address recipient, uint256 numberOfAvatars) external override {
        require(msg.sender == _ethlingsAddress, "Only callable by Ethlings contract");
        _mint(recipient, INITIAL_ALLOTMENT.mul(numberOfAvatars));
    }

    function burn(address sender, uint256 amount) external override {
        require(msg.sender == _ethlingsAddress, "Only callable by Ethlings contract");
        _burn(sender, amount);
    }
}

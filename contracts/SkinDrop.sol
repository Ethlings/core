// SPDX-License-Identifier: MIT

pragma solidity >= 0.6.0;

import "./lib/IERC1155Receiver.sol";
import "./lib/ReentrancyGuard.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";
import "./IEthlings.sol";
import "./lib/IERC1155.sol";
import "./lib/ERC165.sol";

contract SkinDrop is IERC1155Receiver, ReentrancyGuard, ERC165 {
    using SafeMath for uint256;

    // Public variables
    uint256 public skinId1;
    uint256 public skinId2;
    
    uint8[7777] public claims;

    IEthlings private _ethlings;
    IERC1155 private _wearables;
    
    event RedeemedSkins(uint256[] ethlingIds, uint256[] selections);

    constructor(address ethlingsAddress, address wearablesAddress, uint256 _skinId1, uint256 _skinId2) public {
        _registerInterface(
            SkinDrop(address(0)).onERC1155Received.selector ^
            SkinDrop(address(0)).onERC1155BatchReceived.selector
        );
        
        _ethlings = IEthlings(ethlingsAddress);
        _wearables = IERC1155(wearablesAddress);
        skinId1 = _skinId1;
        skinId2 = _skinId2;
    }
    
    function claim(uint256[] memory avatarIds, uint256[] memory selections) public nonReentrant {
        require(avatarIds.length == selections.length, "Invalid input lengths");
        uint256 avatarId;
        uint256 index;
        uint256 count1 = 0;
        uint256 count2 = 0;
        for (uint i = 0; i < avatarIds.length; i++) {
            avatarId = avatarIds[i];
            require(_ethlings.ownerOf(avatarId) == msg.sender, "Sender is not the owner");
            index = ((avatarId >> 224) & 0x3FFF) - 1; // avatar numbers start at 1, not 0
            require(claims[index] == 0, "Skin already claimed");
            
            require(selections[i] == 1 || selections[i] == 2, "Invalid selection");
            if (selections[i] == 1) {
                claims[index] = 1;
                count1 = count1.add(1);
            } else {
                claims[index] = 2;
                count2 = count2.add(1);
            }
        }
        
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = skinId1;
        tokenIds[1] = skinId2;
        
        uint256[] memory counts = new uint256[](2);
        counts[0] = count1;
        counts[1] = count2;
        
        _wearables.safeBatchTransferFrom(
            address(this), 
            msg.sender, 
            tokenIds,
            counts, 
            ""
        );
        
        emit RedeemedSkins(avatarIds, selections);
    }
    
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}

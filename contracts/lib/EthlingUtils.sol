// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeMath.sol";

library EthlingUtils {
    using SafeMath for uint256;

    // set to 1 if a token is an original, set to 0 if a token is a print
    // note: any token with id > 2^224 is an avatar
    uint256 constant ORIGINAL_FLAG_BIT = 1 << 208;

    /**
     * @dev generates "random" values for an avatar
     * @param avatarNumber the serial number of the avatar to create
     */
    function generateAvatar(uint256 avatarNumber) internal view returns (uint256, uint256) {
        // generate entropy using block values, sender, and serial number
        bytes32 hash = keccak256(abi.encodePacked(block.number, blockhash(block.number - 1), msg.sender, avatarNumber));
        
        uint256 speciesValue = uint256(uint8(hash[0]));
        // value from 0-3 inclusive
        uint256 species;
        // value from 0-3 for species == 0, otherwise 0-1
        uint256 color;
        if (speciesValue < 1) { // 1 / 256
            species = 3;
            color = uint8(hash[1]) > 51 ? 0 : 1; // 1/5 species #3 have a special color
        } else if (speciesValue < 13) { // 1 + 12 / 256
            species = 2;
            color = uint8(hash[1]) > 51 ? 0 : 1; // 1/5 species #2 have a special color
        } else if (speciesValue < 64) { // 13 + 20% of 256
            species = 1;
            color = uint8(hash[1]) > 51 ? 0 : 1; // 1/5 species #1 have a special color
        } else {
            species = 0;
            color = uint8(hash[1]) % 4; // equal distribution of color for species #0
        }
        // generate the slots that are customizable for this avatar
        uint16 slots = generateSlots(species, hash);
        
        // pack the avatar's defining information into the top 32 bits
        uint256 avatarId = uint256(uint256(species) << 254) | uint256(slots) << 240 | uint256(color) << 238 |  avatarNumber << 224;
        // assign clothing to the avatar
        uint256 wearables = assignWearables(slots, hash);
        return (avatarId, avatarId | wearables);
    }

    /**
     * @dev randomly decides if each slot on an avatar is unlocked / locked, with chances being species dependent
     * @param species the species of the avatar to generate slot availability for
     * @param hash random values, uses indicies [19, 31]
     * @return bit mask of 1 for unlocked slot, 0 for locked slot
     */
    function generateSlots(uint256 species, bytes32 hash) internal pure returns (uint16) {
        uint16 slots = 0;
        // for each slot...
        for (uint256 i = 0; i < MAX_SLOTS(); i++) {
            // move over our mask by one to open up a new bit
            slots = slots << 1;
            // 1. get a random value from hash (going backwards to not overlap with random values used in generateAvatar function)
            // 2. species #0 has a 50% chance of unlock, species #1 has 55%, species #2 has 60%, species #3 has 65%
            // NOTE: 5% of 256 is ~13 and > 127 = 50%; we use this to generate the ratios for each species on the fly
            // 3. if the random value from 1 is greater than the species dependent value, set a 1, otherwise a 0
            slots = uint8(hash[31 - i]) > (127 - species * 13) ? slots | 1 : slots;
        }
        return slots;
    }

    /**
     * @dev randomly assigns wearables to customizable slots with values [1,20]. [1,10] are rarer than [11,20]
     *      assumes that wearables with ID [1,20] have already been created
     * @param slots the slot customizability for the avatar
     * @param hash random values, uses indices [7,18]
     * @return bit mask of all assigned wearables in each slot, excluding 13th slot
     */
    function assignWearables(uint16 slots, bytes32 hash) internal pure returns (uint256) {
        uint256 worn = 0;
        uint8 rand;
        // for each slot EXCEPT auxiliary1 and auxiliary 2
        for (uint256 i = 0; i < MAX_SLOTS() - 2; i++) {
            if (slots & 1 == 1) { // if the avatar can wear wearable in this slot
                rand = uint8(hash[31 - i - MAX_SLOTS()]);
                if (rand >= 246) { // 1 / 256 chance to receive a wearable with an id from [1,10]
                    worn |= uint256(rand - 245) << (i * 16);
                } else if (rand >= 46) { // 20 / 256 chance to receive a wearable with an id from [11,20]
                    worn |= uint256((rand - 46)  / 20 + 11) << (i * 16);
                }
                // 46 / 256 chance to not receive a piece of clothing
            }
            slots >>= 1;
        }
        return worn;
    }
    
    /**
     * @dev get only bits associated with slot
     * @param store the value to mask from
     * @param slot the location of the data (based on 16 bits per slot)
     * @return masked bits of the data store in the associated slot
     */
    function maskStoreAtSlot(uint256 store, uint256 slot) internal pure returns (uint256) {
        return store & (uint256(0xFFFF) << (slot * 16));
    }
    
    /**
     * @dev get the value stored in a slot
     * @param store the data store to mask from
     * @param slot the location of the data (based on 16 bits per slot)
     * @return the value stored in the associated slot
     */
    function valueInSlot(uint256 store, uint256 slot) internal pure returns (uint16) {
        uint256 mask = uint256(0xFFFF) << (slot * 16);
        return uint16((store & mask) >> (slot * 16));
    }
    
    /**
     * @dev create a data store intialized with a value in a slot
     * @param value the data store to store in the data
     * @param slot the location to place the data (based on 16 bits per slot)
     * @return the initialized data store
     */
    function storeForValueInSlot(uint16 value, uint256 slot) internal pure returns (uint256) {
        return uint256(value) << (slot * 16);
    }
    
    /**
     * @dev remove data stored in a slot
     * @param store the data store to remove data from
     * @param slot the location of the data to remove (based on 16 bits per slot)
     * @return the updated data store
     */
    function zeroValueInSlot(uint256 store, uint256 slot) internal pure returns (uint256) {
        return store & ~(uint256(0xFFFF) << (slot * 16));
    }
    
    /**
     * @dev increment a 16bit value in a data store
     * @param store the data store to update
     * @param slot the location of the data (based on 16 bits per slot)
     * @return the updated data store
     */
    function incrementValueInSlot(uint256 store, uint256 slot) internal pure returns (uint256) {
        return store + (uint256(1) << (slot * 16));
    }
    
    /**
     * @dev checks to see if a slot is available on an avatar
     * @param avatar the avatar to check
     * @param slot the slot to check (should be 0-12 inclusive)
     * @return true if the slot is unlocked, false if not
     */
    function isAvailableSlot(uint256 avatar, uint256 slot) internal pure returns (bool) {
        avatar = avatar >> 240;
        return avatar & (uint256(1) << slot) > 0;
    }

    /**
     * @dev checks to see if a token is an original
     * @param id the id of the token
     * @return true if it's an original, false if not
     */
    function isOriginal(uint256 id) internal pure returns (bool) {
        return id & ORIGINAL_FLAG_BIT > 0;
    }

    /**
     * @dev converts an originalId to its associated printId
     * @param originalId the printId to convert
     * @return the associated printId
     */
    function getPrintFromOriginal(uint256 originalId) internal pure returns (uint256) {
        return originalId & ~ORIGINAL_FLAG_BIT;
    }
    
    /**
     * @dev converts an printId to its associated originalId
     * @param printId the originalId to convert
     * @return the associated originalId
     */
    function getOriginalFromPrint(uint256 printId) internal pure returns (uint256) {
        return printId | ORIGINAL_FLAG_BIT;
    }
    
    /**
     * @dev the maximum number of slots available on an avatar
     * @return maximum slots
     */
    function MAX_SLOTS() internal pure returns (uint256) {
        return 13;
    }

    /**
     * @dev replaces the available slots on an avatar, used for rerolls
     * @param avatarId the avatarId to update
     * @param slots the new set of slots to be available
     * @return the new avatarId
     */
    function replaceSlots(uint256 avatarId, uint16 slots) internal pure returns (uint256) {
        avatarId = (avatarId & ~(uint256(0x1FFF) << 240));
        avatarId = avatarId | (uint256(slots) << 240);
        return avatarId;
    }

    /**
     * @dev checks to see if an avatar is wearing any wearables
     * @param avatar the avatar's data
     * @return true if it's not wearing any wearables, false if it is
     */
    function isAvatarDefault(uint256 avatar) internal pure returns (bool) {
        return ((avatar << 48) >> 48) == 0;
    }

    /**
     * @dev gets an avatar's serial number
     * @param avatarId the avatarId to read from
     * @return the serial number
     */
    function getAvatarNumber(uint256 avatarId) internal pure returns (uint16) {
        return uint16(avatarId >> 224) & 0x3FFF;
    }

    /**
     * @dev gets an avatar's available slots
     * @param avatarId the avatarId to read from
     * @return the available slots as a bit mask
     */
    function getAvatarSlots(uint256 avatarId) internal pure returns (uint16) {
        return uint16(avatarId >> 240) & 0x1FFF;
    }

    /**
     * @dev changes a slot from locked to unlocked, used for unlocks
     * @param avatarId the avatarId to update
     * @param slot the slot to unlock (0-12 inclusive)
     * @return the updated avatarId
     */
    function addSlot(uint256 avatarId, uint16 slot) internal pure returns (uint256) {
        require(avatarId & (uint256(1) << (slot + 240)) == 0, "Slot already unlocked");
        avatarId = avatarId | (uint256(1) << (slot + 240));
        return avatarId;
    }

    /**
     * @dev copies wearables from one avatar to another, used during unlocks to keep the escrowed wearables on the new avatar
     * @param oldAvatar the avatar to copy from
     * @param newAvatar the avatar to copy to
     * @return the new avatar with copied wearables
     */
    function copySlotValues(uint256 oldAvatar, uint256 newAvatar) internal pure returns (uint256) {
        return (newAvatar & (~(uint256(1 << 224) - 1))) | (oldAvatar & (uint256(1 << 224) - 1));
    }
}
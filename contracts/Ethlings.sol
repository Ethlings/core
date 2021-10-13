// SPDX-License-Identifier: MIT

pragma solidity >= 0.6.0;

import "./lib/Ownable.sol";
import "./lib/EthlingUtils.sol";
import "./lib/SafeERC20.sol";
import "./lib/ReentrancyGuard.sol";
import "./IEthlings.sol";
import "./ChangeToken.sol";
import "./Wearables.sol";
import "./lib/ERC721.sol";

contract Ethlings is 
    IEthlings, 
    Ownable, 
    ReentrancyGuard, 
    ERC721
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool private _locked = false;
    
    // maximum number of avatars to exist
    uint256 constant MAX_AVATARS = 7777;
    // current number of avatars in existence
    uint256 public avatarsMinted = 0;
    // mapping from avatarId to the data associated with an avatar (including worn wearables)
    mapping(uint256 => uint256) public avatars;

    // cost to reroll available slots
    uint256 public constant REROLL_COST = 2000 * 10 ** 18;
    // cost to unlock a slot
    uint256 public constant UNLOCK_COST = 10000 * 10 ** 18;
    
    

    // address to withdraw funds
    address payable public _teamAddress;
    IERC20 public immutable currency;
    IWearables public immutable wearables;
    IChangeToken public immutable changeToken;

    event AvatarChanged(
        uint256 avatarId
    );
    event AvatarSlotsRerolled(
        uint256 oldAvatarId,
        uint256 newAvatarId
    );
    event AvatarSlotUnlocked(
        uint256 oldAvatarId,
        uint256 newAvatarId
    );
    event TeamAddressChanged(
        address teamAddress
    );
    
    constructor(
        string memory _uri,
        address _currencyAddress,
        address _changeTokenAddress, 
        address _wearablesAddress
    ) ERC721("Ethlings", "😉") public {
        _setBaseURI(_uri);

        _teamAddress = _msgSender();
        
        currency = IERC20(_currencyAddress);
        changeToken = IChangeToken(_changeTokenAddress);
        wearables = IWearables(_wearablesAddress);
    }

    /***********************************|
    |        Modifiers                  |
    |__________________________________*/

    modifier onlyUnlocked() {
        require(!_locked, "Contract is locked");
        _;
    }

    /***********************************|
    |        User Interactions          |
    |__________________________________*/

    /**
     * @notice creates randomized avatars
     * @param numberOfAvatars the number of avatars to create
     */
    function createAvatars(uint256 numberOfAvatars) external nonReentrant onlyUnlocked {
        require(avatarsMinted.add(numberOfAvatars) <= MAX_AVATARS, "Exceeds max avatar supply");
        require(numberOfAvatars > 0, "Cannot mint 0 avatars");
        require(numberOfAvatars <= 20, "Cannot mint more than 20 avatars at once");

        currency.safeTransferFrom(_msgSender(), address(this), numberOfAvatars.mul(avatarCost()));

        uint256 avatarId;
        uint256 avatar;
        uint256[] memory avatarIds = new uint256[](numberOfAvatars);
        for (uint i = 0; i < numberOfAvatars; i++) {
            avatarsMinted = avatarsMinted + 1;
            (avatarId, avatar) = EthlingUtils.generateAvatar(avatarsMinted);
            avatars[avatarId] = avatar;
            avatarIds[i] = avatarId;
            _safeMint(_msgSender(), avatarId);
            emit AvatarChanged(avatar);
        }

        changeToken.mintOnAvatarCreation(_msgSender(), numberOfAvatars);
    }

    /**
     * @notice re-randomizes the slots that are customizable for a given avatar
     * @param avatarId the avatar to re-randomize
     * @return the id of the new avatar (old one is burned)
     */
    function reroll(uint256 avatarId) external nonReentrant onlyUnlocked returns (uint256) {
        require(ownerOf(avatarId) == _msgSender(), "Invalid avatar");
        require(EthlingUtils.isAvatarDefault(avatars[avatarId]), "Must remove all prints before rerolling");
        (uint256 newAvatarId, ) = EthlingUtils.generateAvatar(EthlingUtils.getAvatarNumber(avatarId));
        newAvatarId = EthlingUtils.replaceSlots(avatarId, EthlingUtils.getAvatarSlots(newAvatarId));
        avatars[newAvatarId] = newAvatarId;
        delete avatars[avatarId];

        changeToken.burn(_msgSender(), REROLL_COST);

        _burn(avatarId);
        _safeMint(_msgSender(), newAvatarId);
        emit AvatarSlotsRerolled(avatarId, newAvatarId);
    }

    /**
     * @notice unlocks a slot on an avatar
     * @param avatarId the avatar to upgrade
     * @param slot 0-12 inclusive for the slot to unlock
     * @return the id of the new avatar (old one is burned)
     */
    function unlock(uint256 avatarId, uint16 slot) external nonReentrant onlyUnlocked returns (uint256) {
        require(ownerOf(avatarId) == _msgSender(), "Invalid avatar");
        require(slot < EthlingUtils.MAX_SLOTS(), "Invalid slot");
        uint256 newAvatarId = EthlingUtils.addSlot(avatarId, slot);
        avatars[newAvatarId] = EthlingUtils.copySlotValues(avatars[avatarId], newAvatarId);
        delete avatars[avatarId];

        changeToken.burn(_msgSender(), UNLOCK_COST);

        _burn(avatarId);
        _safeMint(_msgSender(), newAvatarId);
        emit AvatarSlotUnlocked(avatarId, newAvatarId);
    }

    /**
     * @notice buys, sells, wears, and removes werables with slippage protection - user should send max ETH they're willing to spend
     * @param avatarId the avatar to update
     * @param prints the originalIds of wearables to print
     * @param burns the originalIds of wearables to burn
     * @param wears all printIds masked together to wear
     * @param removes all printIds masked together to remove
     * @param maximumSpent maximum amount sender is willing to spend when printing to prevent slippage
     * @param minimumEarned minimum amount received by sender when burning to prevent slippage
     */
    function checkout(
        uint256 avatarId,
        uint256[] memory prints, 
        uint256[] memory burns, 
        uint256 wears, 
        uint256 removes,
        uint256 maximumSpent,
        uint256 minimumEarned) external nonReentrant onlyUnlocked {
        
        uint256 available = maximumSpent;
        
        // remove any items from the avatar
        if (removes > 0)
            _remove(avatarId, removes);

        // burn any prints, account for ETH earned
        uint256 burnPrice;
        for (uint i = 0; i < burns.length; i++) {
            burnPrice = wearables._burnPrint(_msgSender(), burns[i]);
            available = available.add(burnPrice);
        }

        // mint any prints, account for ETH spent
        uint256 printPrice;
        for (uint i = 0; i < prints.length; i++) {
            printPrice = wearables._print(_msgSender(), prints[i], available);
            //fails when spending exceeds maximum spent
            available = available.sub(printPrice); 
        }
        
        require(available >= minimumEarned, "Did not earn enough");
        
        if (available > maximumSpent) {
            // stop if not enough ETH was earned on burns after spending on prints
            require(available - maximumSpent > minimumEarned, "Did not earn enough");
            currency.safeTransfer(_msgSender(), available - maximumSpent); // return funds
        } else if (available <= maximumSpent) {
            currency.safeTransferFrom(_msgSender(), address(this), maximumSpent - available); // spend funds
        }

        // wear any items
        if (wears > 0)
            _wear(avatarId, wears);

        // if the avatar changed, emit an event
        if (removes > 0 || wears > 0)
            emit AvatarChanged(avatarId);
    }

    /***********************************|
    |        Release Reserve            |
    |__________________________________*/

    /**
     * @notice burns an original and releases the funds under the bonding curve
     * @param originalId the original to brun
     */
    function releaseBondingCurve(uint256 originalId, address destination) external {
        uint256 releaseAmount = wearables._releaseBondingCurve(_msgSender(), originalId);
        currency.safeTransfer(destination, releaseAmount);
    }

    /***********************************|
    |        Public Getters             |
    |__________________________________*/

    /**
     * @notice current cost to create a single avatar
     * @return cost to create
     */
    function avatarCost() public pure returns (uint256) {
        return 0.1111 ether;
    }

    /**
     * @notice cost to print and burn a set of prints
     * @param prints the originalIds to print off of
     * @param burns the originalIds to burn associated prints of
     * @return earn the amount earned
     * @return spend the amount spent
     */
    function calculateNetCost(uint256[] memory prints, uint256[] memory burns) external view returns (uint256 earn, uint256 spend) {
        uint256 _spend =  0;
        for (uint i = 0; i < prints.length; i++) {
            _spend = _spend.add(wearables.getCurrentPrintPrice(prints[i]));
        }
        
        uint256 _earn = 0;
        for (uint i = 0; i < burns.length; i++) {
            _earn = _earn.add(wearables.getCurrentBurnPrice(burns[i]));
        }

        return (_earn, _spend);
    }

    /**
     * @notice checks whether or not an avatar with a specific ID exists
     * @param avatarId the id of the avatar to check
     * @return whether or not it exists
     */
    function avatarExists(uint256 avatarId) external view override returns (bool) {
        return _exists(avatarId);
    }

    /***********************************|
    |        Internal                   |
    |__________________________________*/
    
    /**
     * @dev loops through mask of prints to wear, puts them in escrow (burns them), and sets them on the avatar's data
     * @param avatarId the avatar to update
     * @param wearable 16 bit printIds masked together
     */
    function _wear(uint256 avatarId, uint256 wearable) private {
        require(ownerOf(avatarId) == _msgSender(), "Invalid avatar");
        uint256 avatar = avatars[avatarId];
        uint256 oldPrint;
        uint256 newPrint;
        // loop through each slot
        for (uint8 i = 0; i < EthlingUtils.MAX_SLOTS(); i = i + 1) {
            // check if there is a print being added to this slot
            newPrint = EthlingUtils.maskStoreAtSlot(wearable, i);
            if (newPrint == 0)
                continue;
            // check to see if this slot is customizable for this avatar
            require(EthlingUtils.isAvailableSlot(avatar, i), "Slot not available on avatar");
            
            // if there is a print currently worn in this slot, redeem it (print it)
            oldPrint = EthlingUtils.maskStoreAtSlot(avatar, i);
            if (oldPrint != 0)
                wearables._redeem(_msgSender(), oldPrint);
                
            // add the new worn print to the avatar and send it to escrow (burn it)
            avatar = EthlingUtils.zeroValueInSlot(avatar, i);
            avatar = avatar | newPrint;
            wearables._escrow(_msgSender(), newPrint);
        }
        // save the new avatar data
        avatars[avatarId] = avatar;
    }

    /**
     * @dev loops through mask of prints to remove, redeems them (prints them), and removes them from the avatar's data
     * @param avatarId the avatar to update
     * @param mask 16 bit values masked together - 0 if don't remove, > 0 if remove
     */
    function _remove(uint256 avatarId, uint256 mask) private {
        require(ownerOf(avatarId) == _msgSender(), "Invalid avatar");
        if (mask == 0)
            return;
        uint256 avatar = avatars[avatarId];
        uint256 printId;
        // loop through each slot
        for (uint8 i = 0; i < EthlingUtils.MAX_SLOTS(); i++) {
            // check if an item is worn in that slot
            bool remove = EthlingUtils.valueInSlot(mask, i) > 0;
            if (!remove)
                continue;
            // check if we should remove item in this slot
            printId = EthlingUtils.maskStoreAtSlot(avatar, i);
            if (printId == 0)
                continue;
            // remove the item and redeem it (print it)
            wearables._redeem(_msgSender(), printId);
            avatar = EthlingUtils.zeroValueInSlot(avatar, i);
        }
        // save the new avatar data
        avatars[avatarId] = avatar;
    }

    /***********************************|
    |        Owner Interactions         |
    |__________________________________*/

    /**
     * @notice withdraws funds that are owed to the project (contract balance - total held in reserve)
     */
    function withdraw() public onlyOwner {
        uint256 withdrawableFunds = currency.balanceOf(address(this)).sub(wearables.getReserve());
        currency.safeTransfer(_teamAddress, withdrawableFunds);
    }

    /**
     * @notice sets the address to send withdrawable funds to
     * @param teamAddress the new destination address
     */
    function setTeamAddress(address payable teamAddress) public onlyOwner {
        _teamAddress = teamAddress;
        emit TeamAddressChanged(teamAddress);
    }

    function setLocked(bool locked) external onlyOwner {
        _locked = locked;
    }
}

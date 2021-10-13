// SPDX-License-Identifier: MIT

pragma solidity >= 0.6.0;

import "./lib/Ownable.sol";
import "./lib/EthlingUtils.sol";
import "./lib/ERC1155.sol";
import "./lib/Strings.sol";
import "./IWearables.sol";

contract Wearables is IWearables, Ownable, ERC1155 {
    using SafeMath for uint256;
    using Strings for uint256;

    uint256 constant SIG_DIGITS = 6;
    
    // every 16 bits counts the number of originals for that slot
    uint256 originalCountStore = 0;
    // total amount of ETH reserved for bonding curve payouts
    uint256 reserveTotal = 0;
    
    // mapping from an original to its owner
    mapping(uint256 => address) public originalToOwner;
    // mapping from an original to its packed data (scalar, expiration, printSupply, reserveAmount)
    mapping(uint256 => uint256) public originalDatas;

    // address of Ethlings contract that can call onlyController functions
    address private _controller;
    
    constructor(string memory _uri) ERC1155("Ethlings Wearables", "🥽", _uri) public {}
    
    /**
     * @notice one time function for setting the controller
     * @param controller address of the controller
     */
    function setController(address controller) public onlyOwner {
        require(_controller == address(0), "Cannot change controller");
        _controller = controller;
    }

    /***********************************|
    |        Modifiers                  |
    |__________________________________*/
    modifier onlyController() {
        require(msg.sender == _controller, "Caller is not the controller");
        _;
    }

    /***********************************|
    |        Owner Interactions         |
    |__________________________________*/
    
    /**
     * @dev mints a batch of originals
     * @param _slots an array of values (between 0-12 inclusive) designating which slot each original can be worn on
     * @param _scalars an array of values (between 0-3 inclusive) designating the bonding curve ramp for each original
     * @param _expirations an array of expirations (seconds since epoch) designating when the bonding period ends for each original
     * @return originalIds_ array of all minted originals
     */
    function batchMint(uint256[] calldata _slots, uint256[] calldata _scalars, uint256[] calldata _expirations) external onlyOwner returns (uint256[] memory originalIds_) {
        require(_slots.length == _scalars.length, "Mismatched input lengths");
        require(_slots.length == _expirations.length, "Mismatched input lengths");
        require(_slots.length <= 32, "Input must be less than 32 items");
        uint256[] memory originalIds = new uint256[](_slots.length);
        uint256[] memory counts = new uint256[](_slots.length);
        uint256 originalId;
        for (uint256 i = 0; i < _slots.length; i++) {
            require(_slots[i] < EthlingUtils.MAX_SLOTS(), "Invalid slot");
            originalCountStore = EthlingUtils.incrementValueInSlot(originalCountStore, _slots[i]);
            originalId = EthlingUtils.getOriginalFromPrint(EthlingUtils.maskStoreAtSlot(originalCountStore, _slots[i]));
            require(originalToOwner[originalId] == address(0), "Invalid ID");
            originalToOwner[originalId] = msg.sender;
            originalDatas[originalId] = packOriginalData(_scalars[i], _expirations[i], 0, 0, 0);

            originalIds[i] = originalId;
            counts[i] = 1;
        }
        _mintBatch(msg.sender, originalIds, counts, "");
        return originalIds;
    }
    
    /***********************************|
    |        Controller Interactions    |
    |__________________________________*/

    /**
     * @dev mints a new Print 
     * @param sender the address that should receive the print
     * @param originalId the originalId that should be printed from
     * @param availableFunds the amount of ETH available to purchase this print from the bonding curve
     * @return printPrice_ the actual cost of the print
     */
    function _print(
        address sender,
        uint256 originalId, 
        uint256 availableFunds) 
    external override onlyController returns (
        uint256 printPrice_
    ) {
        require(originalToOwner[originalId] != address(0), "Original does not exist");

        uint256 originalData = originalDatas[originalId];
        require(block.timestamp < unpackExpiration(originalData), "Printing period expired");

        uint256 newSupply = unpackPrintSupply(originalData).add(1);
        uint256 printPrice = getPrintPrice(originalId, newSupply);
        require (availableFunds >= printPrice, "Insufficient funds");
        
        originalData = updatePrintSupply(originalData, newSupply);
        uint256 newReserveAmount = unpackReserveAmount(originalData).add(printPrice.mul(93).div(100));
        originalData = updateReserveAmount(originalData, newReserveAmount);

        uint256 newRoyaltyAmount = unpackRoyaltyAmount(originalData).add(printPrice.mul(7).div(100));
        originalData = updateRoyaltyAmount(originalData, newRoyaltyAmount);
        originalDatas[originalId] = originalData;

        reserveTotal = reserveTotal.add(printPrice);
                
        uint256 printId = EthlingUtils.getPrintFromOriginal(originalId);
        _mint(sender, printId, 1, "");

        return printPrice;
    }
    
    /**
     * @dev burns a Print 
     * @param sender the address that should burn the print
     * @param originalId the originalId that of the print should be burned
     * @return burnPrice_ the actual amount returned from the burn
     */
    function _burnPrint(address sender, uint256 originalId) external override onlyController returns (uint256 burnPrice_) {
        require(originalToOwner[originalId] != address(0), "Original does not exist");

        uint256 originalData = originalDatas[originalId];
        require(block.timestamp < unpackExpiration(originalData), "Burning period expired");

        uint256 oldSupply = unpackPrintSupply(originalData);
        uint256 burnPrice = getBurnPrice(originalId, oldSupply);
        
        originalData = updatePrintSupply(originalData, oldSupply.sub(1));
        uint256 newReserveAmount = unpackReserveAmount(originalData).sub(burnPrice);
        originalData = updateReserveAmount(originalData, newReserveAmount);
        originalDatas[originalId] = originalData;

        reserveTotal = reserveTotal.sub(burnPrice);

        uint256 printId = EthlingUtils.getPrintFromOriginal(originalId);
        _burn(sender, printId, 1);
        
        return burnPrice;
    }

    /**
     * @dev burns a print that has been added to an Ethling
     * @param owner the address of the owner of the Ethling
     * @param printId the ID of the print to escrow
     */
    function _escrow(address owner, uint256 printId) external override onlyController {
        _burn(owner, printId, 1);
    }

    /**
     * @dev mints a print that has been removed from an Ethling
     * @param owner the address of the owner of the Ethling
     * @param printId the ID of the print to redeem
     */
    function _redeem(address owner, uint256 printId) external override onlyController {
        _mint(owner, printId, 1, "");
    }

    /***********************************|
    |        Public Getters             |
    |__________________________________*/

    /**
     * @notice gets the price to print from an original for a given supply
     * @param originalId the original to print from
     * @param printNumber the associated print number to get the price for
     * @return price_ the price to print
     */
    function getPrintPrice(uint256 originalId, uint256 printNumber) public view returns (uint256 price_) {
        require(originalToOwner[originalId] != address(0), "Invalid id");
        uint256 decimals = 10 ** SIG_DIGITS;
        uint256 scalar = unpackScalar(originalDatas[originalId]);
        if (scalar == 0) { // .005 + .0001x
            return decimals.mul(printNumber).div(10000).add(decimals.div(200)).mul(1 ether).div(decimals); 
        } else if (scalar == 1) { // .015 + .00005x^2
            return decimals.mul(printNumber.mul(printNumber)).div(20000).add(decimals.mul(15).div(1000)).mul(1 ether).div(decimals);
        } else if (scalar == 2) { // 1.03^x - 1
            uint256 price = decimals; // multiply by 1.03^10 to avoid overflow
            while (printNumber >= 10) {
                price = price.mul(103 ** 10).div(100 ** 10);
                printNumber = printNumber.sub(10);
            } 
            // include remaining prints
            price = price.mul(103 ** printNumber).div(100 ** printNumber); 
            return price.sub(decimals).mul(1 ether).div(decimals);
        } else { // .25x!
            uint256 price = 0.25 ether;
            for (uint256 i = 2; i <= printNumber; i++)
                price = price.mul(i);
            return price;
        }
    }

    /**
     * @notice gets the current price to print from an original
     * @param originalId the original to print from
     * @return price_ the current price to print
     */
    function getCurrentPrintPrice(uint256 originalId) public view override returns (uint256 price_) {
        return getPrintPrice(originalId, unpackPrintSupply(originalDatas[originalId]).add(1));
    }
    
    /**
     * @notice gets the value of burning a print for a given supply
     * @param originalId the associated original to be burned
     * @param supply the associated supply amount to get the burn price for
     * @return price_ the value for the burn
     */
    function getBurnPrice(uint256 originalId, uint256 supply) public view returns (uint256 price_) {
        uint256 printPrice = getPrintPrice(originalId, supply);
        return printPrice.mul(93).div(100);
    }

    /** 
     * @notice gets the current value of burning a print
     * @param originalId the associated original to be burned
     * @return price_ the current value for the burn
     */
    function getCurrentBurnPrice(uint256 originalId) public view override returns (uint256 price_) {
        return getBurnPrice(originalId, unpackPrintSupply(originalDatas[originalId]));
    }

    /**
     * @notice returns a metadata URL for the specific token
     * @param tokenId the id of the original or print
     * @return the URL of the metadata
     */
     function uri(uint256 tokenId) external override view returns (string memory) {
         return string(abi.encodePacked(_uri, tokenId.toString()));
     }

    /** 
     * @notice gets the current reserve total
     * @return reserveTotal_ the reserve total
     */
    function getReserve() public view override returns (uint256 reserveTotal_) {
        return reserveTotal;
    }

    function getScalar(uint256 originalId) public view returns (uint256) {
        return unpackScalar(originalDatas[originalId]);
    }

    function getExpiration(uint256 originalId) public view returns (uint256) {
        return unpackExpiration(originalDatas[originalId]);
    }

    function getPrintSupply(uint256 originalId) public view returns (uint256) {
        return unpackPrintSupply(originalDatas[originalId]);
    }

    function getReserveAmount(uint256 originalId) public view returns (uint256) {
        return unpackReserveAmount(originalDatas[originalId]);
    }

    function getRoyaltyAmount(uint256 originalId) public view returns (uint256) {
        return unpackRoyaltyAmount(originalDatas[originalId]);
    }

    /***********************************|
    |        Original Owner             |
    |__________________________________*/

    /**
     * @dev burns and original and releases the bonding curve 
     * @param owner the sender of the transaction
     * @param originalId the original that should be burned and whose curve should be released
     * @return releaseAmount_ the amount of ETH released from the curve, less project fees
     */
    function _releaseBondingCurve(address owner, uint256 originalId) external override onlyController returns (uint256 releaseAmount_) {
        require(originalToOwner[originalId] == owner, "Invalid original");
        uint256 originalData = originalDatas[originalId];
        require(block.timestamp >= unpackExpiration(originalData), "Bonding curve not yet expired");
        uint256 releaseAmount = unpackReserveAmount(originalData).add(unpackRoyaltyAmount(originalData));
        reserveTotal = reserveTotal.sub(releaseAmount);
        _burn(owner, originalId, 1);
        return releaseAmount.mul(95).div(100);
    }

    /***********************************|
    |        Internal                   |
    |__________________________________*/

    /**
     * @dev called before token transfer to make sure we update current owner associations
     * @param operator the caller of the transfer
     * @param from the address being sent from
     * @param to the address being sent to
     * @param ids the tokens being transferred
     * @param amounts the amounts of each token being transferred
     * @param data passed data
     */    
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        uint256 originalId;
        for (uint256 i = 0; i < ids.length; i++) {
            // If token is original, keep track of owner so can send them fees
            if (EthlingUtils.isOriginal(ids[i])) {
                originalId = ids[i];
                require(!(to == address(0) && block.timestamp < unpackExpiration(originalDatas[originalId])), "Cannot burn unexpired original");
                originalToOwner[originalId] = to;
            }
        }
    } 

    /**
     * @dev pack values into 256 bits for efficiency
     * @param scalar value 0-3 representing print pricing curve for the original (2 bits; 254-255)
     * @param expiration seconds since epoch when bonding curve period will end (40 bits; 214-253)
     * @param printSupply number of prints currently in existence for this original (20 bits; 194-213) - assumes < 1,048,576 prints per original
     * @param reserveAmount amount of ETH currently locked in reserve for this bonding curve (97 bits; 97-193)
     * @param royaltyAmount amount of ETH earned in royalties for this bonding curve (97 bits; 0-96)
     * @return packed value
     */
    function packOriginalData(uint256 scalar, uint256 expiration, uint256 printSupply, uint256 reserveAmount, uint256 royaltyAmount) internal pure returns (uint256) {
        return 
            ((scalar & 0x3) << 254) | 
            ((expiration & 0xFFFFFFFFFF) << 214) | 
            ((printSupply & 0xFFFFF) << 194) | 
            ((reserveAmount & ((1 << 97) - 1)) << 97) | 
            (royaltyAmount & ((1 << 97) - 1));
    }

    /**
     * @dev get bits 254-255
     * @param originalData data to unpack
     * @return value 0-3 representing print pricing curve for the original
     */
    function unpackScalar(uint256 originalData) internal pure returns (uint256) {
        return originalData >> 254;
    }

    /**
     * @dev get bits 214-253
     * @param originalData data to unpack
     * @return seconds since epoch when bonding curve period will end
     */
    function unpackExpiration(uint256 originalData) internal pure returns (uint256) {
        return (originalData >> 214) & 0xFFFFFFFFFF;
    }

    /** 
     * @dev get bits 194-213
     * @param originalData data to unpack
     * @return number of prints currently in existence for this original
     */
    function unpackPrintSupply(uint256 originalData) internal pure returns (uint256) {
        return (originalData >> 194) & 0xFFFFF;
    }

    /**
     * @dev get bits 97-193
     * @param originalData data to unpack
     * @return amount of ETH currently locked in reserve for this bondind curve
     */
    function unpackReserveAmount(uint256 originalData) internal pure returns (uint256) {
        return (originalData >> 97) & ((1 << 97) - 1);
    }

    /**
     * @dev get bits 0-96
     * @param originalData data to unpack
     * @return mount of ETH earned in royalties for this bonding curve
     */
    function unpackRoyaltyAmount(uint256 originalData) internal pure returns (uint256) {
        return originalData & ((1 << 97) - 1);
    }

    /**
     * @dev updates bits 170-189
     * @param originalData data to update
     * @param printSupply new print supply to insert (20 bit max)
     * @return updated data
     */
    function updatePrintSupply(uint256 originalData, uint256 printSupply) internal pure returns (uint256) {
        uint256 bitMask = 0xFFFFF << 194;
        return (originalData & (~bitMask)) | ((printSupply & 0xFFFFF) << 194);
    }

    /**
     * @dev updates bits 97-193
     * @param originalData data to update
     * @param reserveAmount new reserve amount to insert (97 bit max)
     * @return updated data
     */
    function updateReserveAmount(uint256 originalData, uint256 reserveAmount) internal pure returns (uint256) {
        uint256 bitMask = ((1 << 97) - 1) << 97;
        return (originalData & (~bitMask)) | ((reserveAmount << 97) & bitMask);
    }

    /**
     * @dev updates bits 0-96
     * @param originalData data to update
     * @param royaltyAmount new royalty amount to insert (97 bit max)
     * @return updated data
     */
    function updateRoyaltyAmount(uint256 originalData, uint256 royaltyAmount) internal pure returns (uint256) {
        uint256 bitMask = ((1 << 97) - 1);
        return (originalData & (~bitMask)) | (royaltyAmount & bitMask);
    }

    /***********************************|
    |        Contract Owner             |
    |__________________________________*/

    /**
     * @dev function to mint a Wearable after expiration
     * @param originalId the original to print off of
     * @param amount the number of prints to mint
     */
    function devMint(uint256 originalId, uint256 amount) external onlyOwner {
        uint256 originalData = originalDatas[originalId];
        require(block.timestamp > unpackExpiration(originalData), "Must be expired");

        uint256 newSupply = unpackPrintSupply(originalData).add(amount);
        originalData = updatePrintSupply(originalData, newSupply);
        originalDatas[originalId] = originalData;

        _mint(owner(), EthlingUtils.getPrintFromOriginal(originalId), amount, "");
    }
}

ETHLINGS

Ethlings is an NFT project that allows users to create their own avatars (ERC721) and customize them, on-chain, with wearable items (ERC1155). The artwork, names, descriptions, and other metadata are stored off chain, but all of the avatars' states and wearables are stored on the blockchain.

# Avatars 

Ethling avatars are ERC721 tokens. Each one is unique with a:
- Serial Number (Incrementing from 1 to 7777)
- Species (0: Human, 1: Monkey, 2: Robot, 3: Alien)
- Subtype ([0, 1, 2, 3]: Human, [0, 1]: Monkey / Robot / Alien)

In addition, there are 13 possible customizable slots on an avatar:
0. Background
1. Legs
2. Shoes
3. Chest
4. Left Arm
5. Right Arm
6. Mouth
7. Eyes
8. Hair
9. Hat
10. Border
11. Auxiliary 1
12. Auxiliary 2

However, not every slot is customizable on every avatar. Each avatar also has a bit mask of 13 bits that store whether or not that avatar is allowed to customize that slot. (i.e. Avatar #15 may have a bit mask of 0000000000011, meaning it can only customize its background and legs).


All of these values - Species, Subtype, and Available Slots - are generated randomly when an avatar is minted.
Here are how the values are calculated:
    
    Serial Number:
        Incremented by 1 for each avatar

    Species:
        ~70% Human (179/256)
        ~25% Monkey (64/256)
        ~4% Robot (10/256)
        ~1% Alien (3/256)
    
    Subtype:
        Human:
            25% distribution of each subtype [0-3]
        Monkey:
            ~20/25 (206/256) - 0
            ~5/25 (50/256) - 1 
        Robot:
            8/10 (206/256) - 0
            2/10 (50/256) - 1
        Alien:
            3/4 - 0
            1/4 - 1

    Slot Avaialability:
        For each slot...
            Humans have a ~50% (128/256) chance of it being available (1)
            Monkeys have a ~55% (141/256) chance of it being available (2)
            Robots have a ~60% (154/256) chance of it being available (3)
            Aliens have a ~65% (167/256) chance of it being available (4)
 
Minting is done by calling the createAvatars() function and any user can generate up to 20 avatars at a time. There is a ramping price associated with these minting an avatar that must be sent in WETH to the contract when calling the function. (approval is required for the contract to transfer the WETH)

An avatar's data is stored in its ID in the following format:
- Bits 254-255: Species
- Bits 240-242: Slot availability
- Bits 238-239: Subtype
- Bits 224-237: Serial Number

In addition, when an avatar is minted, it may be randomly assigned a Wearable for each available slot besides the final 2. (Slots [0, 10] should be randomly assigned, but not slots [11,12])
Given that an avatar has a specific unlocked slot, it has the following chances for the Wearable given in that slot:
- 10 / 256 chance to recieve a wearable with ID [1, 10]. (each Wearable individually has a 1 / 256 chance)
- 200 / 256 chance to receive a wearable with ID [11, 20]. (each Wearable individually has a 20 / 256 chance)
- 46 / 256 chance to not receive a wearable

** We do not provide checks, but minting should only be performed after the first 20 originals have been minted for each Wearable slot

# Change Token

In addition, every avatar minted releases 1,000 ChangeToken to the minter. ChangeToken is an ERC20 token that can be used to alter avatar's slot availability. There are three ways to get ChangeToken:
1. Receive 1,000 when minting an avatar
2. Earn 1,000 over the course of a year (starting when the project is deployed) for each avatar owned by calling claim() on the ChangeToken contract
3. Buy it on an exchange

The owner of the contract can claim (10,000,000 - 7777000) = 2223000 ChangeToken over the same emission period (1 year).

ChangeToken has 2 uses:
1. Reroll your avatar's available slots - a completely random reroll
    - Costs 2,000 ChangeToken
    - Cannot be done if the avatar is wearing clothing
    - A reroll will burn the avatar and create a new one with a new encoded ID (same serial number, species, subtype, different slots)
2. Upgrade a slot from unavailable to available - 1 slot at a time
    - Costs 10,000 ChangeToken
    - Cannot be done on a slot that's already available
    - An unlock will burn the avatar and create a new avatar with a new encoded ID (same serial number, species, subtype, same slots except the one that was upgraded)

ChangeToken is burned on use.

# Wearables

Wearables are ERC1155 tokens of two types: Originals and Prints.

There will only every be 1 Original of any give ID, but there may be several Prints. Prints are copies of an Original. The only difference in ID is that Originals have the 208th bit set to 1.

A wearable is meant to represent a piece of clothing, a body part, or an accessory that can be added to an avatar. Each is defined by an Original which has its own bonding curve. These bonding curves allow a user to "print" a copy of the Original and mint a Print of their own with the associated Original's attributes (these attributes are stored off-chain). 

Originals can only be minted by the project owner and have an associated "scalar" (explained below), slot (the slot they fit into on the avatar), and expiration (the timestamp at which printing / burning ends on that Original). Each Original encodes its slot in its ID and all other values in a packed 256 bit integer. The slot encoding is as follows:

There are 16, 16 bit words in a 256 bit integer. The lowest order 13 of them are used to store the serial number of the original in that slot. For instance, the 10th minted original that fits in the Leg slot (slot 1) would be encoded as:
_ _ _ 0x1 _ _ _ _ _ _ _ _ _ _ 0xa _ 

And the 176th original that fits in the Foreground slot (slot 11) would be encoded as:
_ _ _ 0x1 0xb0 _ _ _ _ _ _ _ _ _ _ _

(note: the 0x1 denotes that this is an original)

A Print made from that original would have the encoding:
_ _ _ _ 0xb0 _ _ _ _ _ _ _ _ _ _ _



The price of a Print goes up each time one is created based on its supply. The formula for calculating the price of Print is defined by the "scalar" value associated with the Original.

An Original's scalar will be an int [0-3] with the following associated curves:
- Linear (0): .005 + .0001x
- Polynomial (1): .015 + .00005x^2
- Exponential (2): 1.03^x - 1
- Factorial (3): 0.25(x!)

All of these prices are listed in ETH where "x" is the current supply of that specific Print + 1 (the supply after the print is completed).

When the WETH is sent to the contract, 93% goes to a reserve and 7% is set aside for as a royalty for the owner of the original.

In addition, a Print can be burned back to the bonding curve. When sending the Print back to the curve as part of a burn, 93% of the *most recent print price for the associated original* is returned back to the Print owner. This mechanic is inspired by EulerBeats.

Once the expiration passes on an Original, all printing and burning will cease for that Original. The owner of the Original can then burn it to receive all of the royalties earned over the lifetime of the Original AND the entire reserve of the bonding curve. However, 5% of these values is retained by the project for withdrawal as a fee.

After this occurs, the supply of that Print is locked and no more will ever exist.

# Interacting with an avatar

A user will customize their avatar by using the checkout() function. To minimize on the number of transactions required to customize their avatar, they can use this function to buy, wear, remove, and sell any clothing they'd like for a specific avatar. 

WETH is transferred to facilitate purchasing all of the prints that occur as part of buying wearables to place on the avatar. However, we first commit all removes and sells first to augment the paid value. 

If a user's prints in a checkout cost 1 WETH, but they're burning 0.6 WETH worth of wearables simultaneously, they will only need to send 0.4 WETH to make the transaction successful. The user setting the "maximumSpent" effectively acts as a slippage mechanic against front runners who may affect the price before purchase.

In the other direction, a user can set a "minimumEarned" value that will revert the transaction if their sells don't net them enough funds. This acts as a slippage safety net, also against frontrunners, who may time their sells to make the user sell at suboptimal prices.

# General deployment

1. Deploy ChangeToken
2. Deploy Wearables
3. Deploy Ethlings
4. Set EthlingsAddress on ChangeToken to Ethlings contract
5. Set Controller on Wearables to Ethlings contract


import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868

access(all) contract Refugee {
    access(all) struct Donation {
        access(all) let id: UInt64
        access(all) let recipient: Address
        access(all) let goalAmount: UFix64
        access(all) let deadline: UFix64
        access(all) var currentAmount: UFix64
        access(all) var donorCount: Int

        init(id: UInt64, recipient: Address, goalAmount: UFix64, deadline: UFix64) {
            self.id = id
            self.recipient = recipient
            self.goalAmount = goalAmount
            self.deadline = deadline
            self.currentAmount = 0.0
            self.donorCount = 0
        }
    }

    access(all) var activeDonations: [Donation]
    access(all) var nextDonationID: UInt64

    access(all) let WUSDCVault: @WUSDC.Vault

    access(all) let AdminStoragePath: StoragePath
    access(all) let AdminPublicPath: PublicPath

    access(all) event DonationCreated(id: UInt64, recipient: Address, goalAmount: UFix64, deadline: UFix64)
    access(all) event DonationReceived(id: UInt64, from: Address, amount: UFix64)
    access(all) event FundsWithdrawn(id: UInt64, amount: UFix64)
    access(all) event DonationRemoved(id: UInt64)

    access(all) resource Admin {
        access(all) fun removeDonation(id: UInt64) {
            pre {
                DonationContract.getActiveDonationIndex(id) != nil: "Donation does not exist"
            }
            
            if let index = DonationContract.getActiveDonationIndex(id) {
                DonationContract.activeDonations.remove(at: index)
                emit DonationRemoved(id: id)
            }
        }
    }

    init() {
        self.activeDonations = []
        self.nextDonationID = 0
        self.WUSDCVault <- WUSDC.createEmptyVault()

        self.AdminStoragePath = /storage/DonationContractAdmin
        self.AdminPublicPath = /public/DonationContractAdmin

        let admin <- create Admin()
        self.account.save(<-admin, to: self.AdminStoragePath)
    }

    access(all) fun createDonation(recipient: Address, goalAmount: UFix64, durationInSeconds: UFix64): UInt64 {
        let deadline = UFix64(getCurrentBlock().timestamp) + durationInSeconds
        let newID = self.nextDonationID
        let newDonation = Donation(id: newID, recipient: recipient, goalAmount: goalAmount, deadline: deadline)
        
        self.activeDonations.append(newDonation)
        self.nextDonationID = self.nextDonationID + 1

        emit DonationCreated(id: newID, recipient: recipient, goalAmount: goalAmount, deadline: deadline)
        return newID
    }

    access(all) fun donate(donationID: UInt64, wusdcVault: @WUSDC.Vault) {
        pre {
            self.getActiveDonationIndex(donationID) != nil: "Donation does not exist"
            getCurrentBlock().timestamp <= self.activeDonations[self.getActiveDonationIndex(donationID)!].deadline: "Donation period has ended"
        }

        let donationIndex = self.getActiveDonationIndex(donationID)!
        let amount = wusdcVault.balance

        // Deposit the WUSDC into the contract's vault
        self.WUSDCVault.deposit(from: <-wusdcVault)

        self.activeDonations[donationIndex].currentAmount = self.activeDonations[donationIndex].currentAmount + amount
        self.activeDonations[donationIndex].donorCount = self.activeDonations[donationIndex].donorCount + 1

        emit DonationReceived(id: donationID, from: self.account.address, amount: amount)

        // Check if goal is reached
        if self.activeDonations[donationIndex].currentAmount >= self.activeDonations[donationIndex].goalAmount {
            self.removeDonation(id: donationID)
        }
    }

    access(all) fun withdrawFunds(donationID: UInt64) {
        pre {
            self.getActiveDonationIndex(donationID) != nil: "Donation does not exist"
            getCurrentBlock().timestamp > self.activeDonations[self.getActiveDonationIndex(donationID)!].deadline: "Donation period has not ended yet"
        }
        let donationIndex = self.getActiveDonationIndex(donationID)!
        let donation = self.activeDonations[donationIndex]
        
        // Transfer the funds to the recipient
        let recipientRef = getAccount(donation.recipient)
            .getCapability(/public/WUSDCReceiver)
            .borrow<&{FungibleToken.Receiver}>()
            ?? panic("Could not borrow receiver reference to the recipient's WUSDC Vault")

        let amountToWithdraw = donation.currentAmount
        let withdrawnVault <- self.WUSDCVault.withdraw(amount: amountToWithdraw)
        recipientRef.deposit(from: <-withdrawnVault)

        emit FundsWithdrawn(id: donationID, amount: amountToWithdraw)

        self.removeDonation(id: donationID)
    }

    access(all) fun getActiveDonations(): [Donation] {
        return self.activeDonations
    }

    access(all) fun getActiveDonationIndex(_ id: UInt64): Int? {
        return self.activeDonations.firstIndex(where: { $0.id == id })
    }

    access(contract) fun removeDonation(id: UInt64) {
        if let index = self.getActiveDonationIndex(id) {
            self.activeDonations.remove(at: index)
            emit DonationRemoved(id: id)
        }
    }
}
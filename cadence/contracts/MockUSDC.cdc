import FungibleToken from 0x9a0766d93b6608b7

access(all) contract MockUSDC: FungibleToken {
    access(all) var totalSupply: UFix64

    access(all) event TokensInitialized(initialSupply: UFix64)
    access(all) event TokensWithdrawn(amount: UFix64, from: Address?)
    access(all) event TokensDeposited(amount: UFix64, to: Address?)

    access(all) resource Vault: FungibleToken.Provider, FungibleToken.Receiver, FungibleToken.Balance {
        access(all) var balance: UFix64

        init(balance: UFix64) {
            self.balance = balance
        }

        access(all) fun withdraw(amount: UFix64): @FungibleToken.Vault {
            self.balance = self.balance - amount
            emit TokensWithdrawn(amount: amount, from: self.owner?.address)
            return <-create Vault(balance: amount)
        }

        access(all) fun deposit(from: @FungibleToken.Vault) {
            let vault <- from as! @MockUSDC.Vault
            self.balance = self.balance + vault.balance
            emit TokensDeposited(amount: vault.balance, to: self.owner?.address)
            vault.balance = 0.0
            destroy vault
        }
    }

    access(all) fun createEmptyVault(): @FungibleToken.Vault {
        return <-create Vault(balance: 0.0)
    }

    init() {
        self.totalSupply = 0.0
        emit TokensInitialized(initialSupply: self.totalSupply)
    }
}
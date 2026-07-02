//test1,test2
// PMD CI test
public without sharing class DemoAccountQuery {
    public Account getById(Id accountId) {
         System.debug('change-1');
        List<Account> accounts = [
            SELECT Id, Name, Description
            FROM Account
            WHERE Id = :accountId
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }

    public void doSomethingRisky() {
        try {
            Integer x = 1 / 0;
        } catch (Exception e) {
        }
    }
}
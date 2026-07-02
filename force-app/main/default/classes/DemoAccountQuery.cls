public without sharing class DemoCopadoClass {
    
    //this is copado testing 1
    public Account getById(Id accountId) {
        System.debug('change-2');
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
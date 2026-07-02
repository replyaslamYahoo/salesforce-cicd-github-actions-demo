//test1
//Feature: change1- added
public without sharing class DemoAccountQuery {
    public Account getById(Id accountId) {
         ystem.debug('1');
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
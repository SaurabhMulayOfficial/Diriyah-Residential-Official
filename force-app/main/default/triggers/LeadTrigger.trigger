/*
    * Use Utility/Service classes to implement the logic. And call those methods from Trigger Handler.
*/

trigger LeadTrigger on Lead (after insert, after update, after delete, after undelete, before insert, before update, before delete) {
    new RES_LeadTriggerHandler().run();   
}
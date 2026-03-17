trigger RES_PendingServiceRoutingTrigger on PendingServiceRouting (before insert, before update, after insert, after update, after delete, after undelete) {
    if(!Test.isRunningTest()){
        new RES_PendingServiceRoutingHandler().run();
    }
}

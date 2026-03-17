trigger RES_PendingServiceRoutingTrigger on PendingServiceRouting (before insert, before update, after insert, after update, after delete, after undelete) {
    new RES_PendingServiceRoutingHandler().run();
}
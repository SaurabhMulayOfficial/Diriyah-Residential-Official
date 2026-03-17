public with sharing class RES_PendingServiceRoutingHandler extends RES_BaseTriggerHandler{

    protected override void afterUpdate() {
        RES_PendingServiceRoutingService.startSLA((List<PendingServiceRouting>)Trigger.new);
    }


}
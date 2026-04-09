/**
 * @class name         : RES_BaseTriggerHandler
 * @description        : Abstract base class for trigger handlers, providing common trigger execution logic.
                         Note: Subclasses should implement the specific before/after methods for handling different trigger events.
 * @author             : Saurabh
 */

public abstract class RES_BaseTriggerHandler {

    public void run() {
        if (Trigger.isBefore) {
            if (Trigger.isInsert){ beforeInsert(); }
            if (Trigger.isUpdate){ beforeUpdate(); }
            if (Trigger.isDelete){ beforeDelete(); }
        }

        if (Trigger.isAfter) {
            if (Trigger.isInsert){ afterInsert(); }
            if (Trigger.isUpdate){ afterUpdate(); }
            if (Trigger.isDelete){ afterDelete(); }
            if (Trigger.isUndelete){ afterUndelete(); }
        }
    }

    protected virtual void beforeInsert() {}
    protected virtual void beforeUpdate() {}
    protected virtual void beforeDelete() {}

    protected virtual void afterInsert() {}
    protected virtual void afterUpdate() {}
    protected virtual void afterDelete() {}
    protected virtual void afterUndelete() {}
}
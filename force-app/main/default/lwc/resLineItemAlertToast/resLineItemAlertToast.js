import { LightningElement } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';

/**
 * DIR-1128: Invisible listener component.
 * Subscribes to the RES_Line_Item_Alert__e platform event and, when an alert is
 * addressed to the current user, shows a toast. This surfaces Quote Line Item
 * validation messages (one product / quantity of 1) for the Browse Catalogs flow,
 * which does not render save-time errors inline. A bell is also sent server-side;
 * this toast is the on-screen equivalent.
 */
export default class ResLineItemAlertToast extends LightningElement {
    channelName = '/event/RES_Line_Item_Alert__e';
    subscription = {};

    connectedCallback() {
        this.registerErrorListener();
        this.handleSubscribe();
    }

    disconnectedCallback() {
        if (this.subscription && Object.keys(this.subscription).length) {
            unsubscribe(this.subscription, () => {});
        }
    }

    handleSubscribe() {
        const messageCallback = (response) => {
            const payload = (response && response.data && response.data.payload) || {};
            const recipient = payload.RecipientUserId__c || '';
            // Only handle alerts raised for the current user (compare 15-char ids).
            if (recipient.substring(0, 15) !== USER_ID.substring(0, 15)) {
                return;
            }
            // The Quote Line editor grid shows this validation message inline; Browse Catalogs
            // shows nothing. Give the inline error a moment to render, then only toast if the
            // message is NOT already visible on screen. This shows the toast for Browse Catalogs
            // (no inline error) while suppressing the redundant toast in the grid editor.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                if (this.isMessageAlreadyVisible()) {
                    return;
                }
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Product could not be added',
                        message: payload.Message__c,
                        variant: 'error',
                        mode: 'dismissable'
                    })
                );
            }, 500);
        };
        subscribe(this.channelName, -1, messageCallback).then((response) => {
            this.subscription = response;
        });
    }

    /**
     * True when the single-product / quantity validation message is already visible on the
     * page (the Quote Line editor grid renders it inline). Browse Catalogs shows nothing, so
     * this returns false there and the toast is shown. Matches distinctive phrases common to
     * all three message variants so it works regardless of which rule was violated.
     */
    isMessageAlreadyVisible() {
        try {
            const bodyText = (document.body && document.body.innerText) || '';
            return (
                bodyText.indexOf('can be added to a quote') !== -1 ||
                bodyText.indexOf('quantity of 1 only') !== -1
            );
        } catch (e) {
            return false;
        }
    }

    registerErrorListener() {
        onError((error) => {
            // eslint-disable-next-line no-console
            console.error('RES_Line_Item_Alert emp API error: ', JSON.stringify(error));
        });
    }
}

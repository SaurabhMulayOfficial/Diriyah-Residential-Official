import { LightningElement, api } from 'lwc';
export default class productSoftHoldBanner extends LightningElement {
    @api header;
    @api body;
    @api variant = 'warning';

    get themeClass() {
        switch (this.variant) {
            case 'info':
                return 'slds-theme_info';
            case 'error':
                return 'slds-theme_error';
            case 'warning':
            default:
                return 'slds-theme_warning';
        }
    }

    get bannerClass() {
        return `slds-notify slds-notify_alert slds-theme_alert-texture slds-p-around_medium ${this.themeClass}`;
    }

    get iconName() {
        switch (this.variant) {
            case 'info':
                return 'utility:info';
            case 'error':
                return 'utility:error';
            case 'warning':
            default:
                return 'utility:warning';
        }
    }
}
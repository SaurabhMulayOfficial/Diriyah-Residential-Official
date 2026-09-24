import { LightningElement, api } from 'lwc';

/**
 * Flow screen component used on the final screen of RES_Create_Payment_Plan. Automatically
 * navigates to the newly created Payment Plan record as soon as it renders, so the user lands
 * on the record instead of having to click a link - matches "User should be redirected to the
 * payment plan product record" in the acceptance criteria.
 *
 * Uses a plain "/<recordId>" URL via window.location instead of NavigationMixin: this flow is
 * launched from a Product list view button as a standalone "/flow/..." page in a new tab, and
 * NavigationMixin.Navigate() doesn't reliably work outside a page embedded in the Lightning App
 * Builder navigation context - it silently no-ops there for both the automatic redirect and the
 * fallback link, which is exactly the "neither works" symptom this replaces. A bare "/<id>" URL
 * resolves correctly in both Lightning Experience and Classic regardless of hosting context.
 */
export default class ResRedirectToRecord extends LightningElement {
    @api recordId;
    @api objectApiName = 'Product2';

    navigated = false;

    get recordUrl() {
        return this.recordId ? `/${this.recordId}` : '#';
    }

    renderedCallback() {
        if (this.navigated || !this.recordId) {
            return;
        }
        this.navigated = true;
        window.location.href = this.recordUrl;
    }
}
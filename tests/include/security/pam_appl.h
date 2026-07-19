#ifndef TEST_PAM_APPL_H
#define TEST_PAM_APPL_H

typedef struct pam_handle pam_handle_t;

#define PAM_RHOST 4

int pam_set_item(pam_handle_t *pamh, int item_type, const void *item);

#endif

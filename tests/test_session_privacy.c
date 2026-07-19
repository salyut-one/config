#include <assert.h>
#include <stddef.h>

#include <security/pam_appl.h>
#include <security/pam_modules.h>

struct pam_handle {
    int unused;
};

static int set_item_result;
static int set_item_calls;
static int last_item_type;
static const void *last_item;

int pam_set_item(pam_handle_t *pamh, int item_type, const void *item)
{
    assert(pamh != NULL);
    set_item_calls++;
    last_item_type = item_type;
    last_item = item;
    return set_item_result;
}

int pam_sm_open_session(pam_handle_t *pamh, int flags,
                        int argc, const char **argv);
int pam_sm_close_session(pam_handle_t *pamh, int flags,
                         int argc, const char **argv);

int main(void)
{
    pam_handle_t handle = {0};

    set_item_result = 17;
    assert(pam_sm_open_session(&handle, 0, 0, NULL) == 17);
    assert(set_item_calls == 1);
    assert(last_item_type == PAM_RHOST);
    assert(last_item == NULL);

    assert(pam_sm_close_session(&handle, 0, 0, NULL) == PAM_SUCCESS);
    assert(set_item_calls == 1);
    return 0;
}

# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;
use base 'basetest';
use testapi;

sub run {
    select_console 'brokenvnc';
}

1;

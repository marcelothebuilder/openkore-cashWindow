############################################################
# cashWindow by Revok
#
# Copyright (c) 2012-2060 Revok
############################################################

package cashWindow;

use strict;
use Plugins;
use lib $Plugins::current_plugin_folder;
use Utils;
use Log qw( warning message error debug );
use Misc;
use Globals;
use Translation;
use Task::Wait;

Plugins::register('cashWindow', 'cashWindow', \&onUnload);

my $hooks = Plugins::addHooks(
	['Network::serverConnect/master', \&addPackets], # with this hook we're sure that servertypes are loaded
	#['packet_pre/cash_window_item_list', \&cash_window_item_list],
);

*Network::Receive::cash_window_shop_open = *cash_window_shop_open;
*Network::Receive::cash_window_buy_result = *cash_window_buy_result;
*Network::Receive::cash_window_item_list = *cash_window_item_list;

my $myCmds = Commands::register(
	['cash', 		"cash system", 			\&cmdCash],
);

my $pluginDir = $Plugins::current_plugin_folder;


sub addPackets {
	my %send_packets = (
		'0844' => ['cash_window_open'], # we don't need to use this, just skip to 0x8C9 | actually, we can use this in order to check for current points
		'0848' => ['cash_window_buy_items', 's s V V s', [qw(len count item_id item_amount tab_code)]], #item_id, item_amount and tab_code could be repeated in order to buy multiple itens at once
		'08C9' => ['cash_window_req_list'],
	);
	
	$messageSender->{packet_list}{$_} = $send_packets{$_} for keys %send_packets;
	
	
	my %recv_packets = (
		'0845' => ['cash_window_shop_open', 'v2', [qw(cash_points kafra_points)]],
		'0849' => ['cash_window_buy_result', 'V s V', [qw(item_id result updated_points)]],
		'08CA' => ['cash_window_item_list', 'v3 a*', [qw(len item_count index item_data)]],
	);
	
	$packetParser->{packet_list}{$_} = $recv_packets{$_} for keys %recv_packets;
	
}

sub sendOpenCashWindowList {
	my $msg = $messageSender->reconstruct({switch => 'cash_window_req_list'});
	$messageSender->sendToServer($msg);
	debug "Sent sendOpenCashList\n", "sendPacket", 2;
}

sub sendCashWindowBuy {
	my ($item_id, $item_amount, $tab_code) = @_;
	my $msg = $messageSender->reconstruct({
			switch => 'cash_window_buy_items',
			len => 16, # always 16 for current implementation
			count => 1, # current _kore_ implementation only allow us to buy 1 item at time
			item_id => $item_id,
			item_amount => $item_amount,
			tab_code => $tab_code,
		});
	$messageSender->sendToServer($msg);
	debug "Sent sendCashListRequest\n", "sendPacket", 2;
}

sub sendCashWindowOpen {
	my $msg = $messageSender->reconstruct({switch => 'cash_window_open'});
	$messageSender->sendToServer($msg);
	debug "Sent sendCashWindowOpen\n", "sendPacket", 2;
}

sub cmdCash {
	my (undef, $input) = @_;
	my ($subCmd, $subArg) = split(' ', $input, 2);
	#warning "cmdCash subcmd $subcmd \n";
	#warning "cmdCash subarg $subarg \n";
	if ($subCmd eq "list") {
		sendOpenCashWindowList();
	} elsif ($subCmd eq "buy") {
		sendCashWindowBuy(6109, 1, 7);
	} elsif ($subCmd eq "points" || $subCmd eq "") {
		sendCashWindowOpen();
	}
}	

sub cash_window_shop_open {
	my ($self, $args) = @_;
	# Should we use $args->{kafra_points} too?
	message TF("You have %s CASH.\n", formatNumber($args->{cash_points})), "info";
}

sub cash_window_item_list {
	my (undef, $args) = @_;
	warning "Received ".$args->{index}."\n";
	$cashWindow{'last_tab'} = $args->{index};
	
	my $i;
	for ($i = 0; ($i < $args->{item_count}); $i++) {
		my $item_id = unpack("v", substr($args->{item_data}, (6 * $i), 2));
		my $item_price = unpack("v", substr($args->{item_data}, 2 + (6 * $i), 2));
		$cashWindow{'items'}{$item_id}{'price'} = $item_price;
		$cashWindow{'items'}{$item_id}{'tab'} = $args->{index};
	}
	
	if ($args->{index} >= 7) {
		cashWindowInventory();
	}
}

sub cash_window_buy_result {
	my ($self, $args) = @_;
	# TODO: implement result messages:
		# SUCCESS			= 0x0,
		# WRONG_TAB?		= 0x1, // we should take care with this, as it's detectable by the server
		# SHORTTAGE_CASH		= 0x2,
		# UNKONWN_ITEM		= 0x3,
		# INVENTORY_WEIGHT		= 0x4,
		# INVENTORY_ITEMCNT		= 0x5,
		# RUNE_OVERCOUNT		= 0x9,
		# EACHITEM_OVERCOUNT		= 0xa,
		# UNKNOWN			= 0xb,
	if ($args->{result} > 0) {
		error TF("Error while buying %s from cash shop. Error code: %s\n", itemNameSimple($args->{item_id}), $args->{result});
	} else {
		message TF("Bought %s from cash shop. Current CASH: %s\n", itemNameSimple($args->{item_id}), formatNumber($args->{updated_points})), "success";
	}
}

sub cashWindowInventory {
	message TF("-------------------- CASH STORE -------------------\n"), "list";
	message TF("Name                                          Price\n"), "list";
	foreach my $key (keys %{$cashWindow{'items'}}) {
		message(swrite(
		"@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @>>>>>>>>>> CASH",
		[itemNameSimple($key), formatNumber($cashWindow{'items'}{$key}{'price'})]),
		"list");
	}
	message("---------------------------------------------------\n", "list");
}


sub onUnload {
	message("Unloading cashWindow... \n");
	Plugins::delHooks($hooks);
	Commands::unregister($myCmds);
}


1;
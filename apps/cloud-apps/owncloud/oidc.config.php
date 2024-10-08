<?php
// DO NOT EDIT THIS FILE BY HAND -- YOUR CHANGES WILL BE OVERWRITTEN
$CONFIG = [
	'openid-connect' => [
		'provider-url' => 'https://idm.vonarx.online/oauth2/openid/owncloud',
		'client-id' => 'owncloud',
		'client-secret' => "{{ environ('OWNCLOUD_OIDC_CLIENTSECRET') }}",
		'loginButtonName' => 'Login with OpenID',
		'mode' => 'userid',
		'search-attribute' => 'sub',
		'auto-provision' => [
			'enabled' => true,
			'update' => [ 'enabled' => true, ],
			'display-name-claim' => 'name',
			'email-claim' => 'email',
			'groups' => [],
		],
	],
];

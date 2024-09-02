<?php
$CONFIG = [
	'openid-connect' => [
		'provider-url' => 'https://idm.vonarx.online/oauth2/openid/owncloud',
		'client-id' => 'owncloud',
		'client-secret' => getenv('OWNCLOUD_OIDC_CLIENTSECRET'),
		'loginButtonName' => 'Login with OpenID',
		'mode' => 'userid',
		'auto-provision' => [
			// explicit enable the auto provisioning mode
			'enabled' => true,
			// enable the user info auto-update mode
			'update' => [ 'enabled' => true, ],
			// documentation about standard claims: https://openid.net/specs/openid-connect-core-1_0.html#StandardClaims
			// only relevant in userid mode,  defines the claim which holds the email of the user
			'email-claim' => 'email',
			// defines the claim which holds the display name of the user
			'display-name-claim' => 'preferred_username',
			// defines the claim which holds the picture of the user - must be a URL
			// 'picture-claim' => 'picture',
			// defines a list of groups to which the newly created user will be added automatically
			'groups' => [ 'admin' ],
		],
	],
];

/**
 * Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
 *
 * Makes two Google Forms in your own Google Drive, each with a Google Sheet
 * that collects the responses:
 *   1. "Maritime Empire - Tester Sign-up & Agreement": tester details plus the
 *      Beta Tester Agreement (EULA + NDA, see beta_tester_agreement.md), with
 *      a parent/guardian step for 13-17 year olds and no entry for under 13s.
 *   2. "Maritime Empire - Tester Feedback": the survey testers fill in after
 *      playing a build.
 *
 * How to run: open https://script.google.com, click New project, delete what's
 * there, paste this whole file, click Save, pick createTesterForms in the
 * function menu, click Run, allow access, then open View > Logs (or the
 * Execution log) for the links.
 *
 * If you change the agreement, change AGREEMENT below and the .md to match.
 */

var GAME = 'Maritime Empire';
var DEVELOPER = 'Rory Ferrick';
var CONTACT = 'roryferrick@gmail.com';
var GOVERNING_LAW = '[STATE / COUNTRY]';
var AGREEMENT_VERSION = '1.0 (8 October 2026)';

var AGREEMENT = [
  ['About this agreement',
    'This agreement is between ' + DEVELOPER + ' ("the Developer") and you, the person testing the game ' +
    '("the Tester"). It covers the test builds of ' + GAME + ' and anything about them you see or hear while ' +
    'testing (together, "the Game"). It combines a licence to play the Game (an end-user licence agreement, or ' +
    'EULA) with a promise to keep it confidential (a non-disclosure agreement, or NDA). Version ' + AGREEMENT_VERSION + '.'],
  ['1. Your licence to play',
    '1.1 The Developer gives you a personal, free, non-exclusive, non-transferable licence to install and play ' +
    'the Game, only to test it and give feedback. The Developer can withdraw this licence at any time.\n\n' +
    '1.2 You must not: share, upload, sell, rent or lend the Game or any build of it, or let anyone else play ' +
    'your copy; copy, decompile, reverse-engineer, data-mine or modify the Game, or extract its files, art, code ' +
    'or data; use cheats, bots or exploits against other players, or keep using a bug for advantage after ' +
    'you\'ve found it (report it instead); remove any copyright or ownership notice.\n\n' +
    '1.3 The Developer owns the Game and all rights in it, including copyright, trademarks (including the names ' +
    '"Maritime Empire" and "Ships") and everything else. This agreement doesn\'t give you ownership of anything.'],
  ['2. Keeping it confidential',
    '2.1 Everything about the Game is confidential until the Developer makes it public: the builds, gameplay, ' +
    'features, art, names, plans, bugs, your test account, and anything the Developer tells you.\n\n' +
    '2.2 Without the Developer\'s written permission (a message or email is enough) you must not: stream, ' +
    'record, post or share screenshots, videos or clips; describe or review the Game publicly, including on ' +
    'social media, forums, Discord servers or in group chats outside the official tester group; show the Game ' +
    'to anyone who hasn\'t signed this agreement.\n\n' +
    '2.3 This doesn\'t cover information that is already public through no fault of yours, or that the law ' +
    'requires you to disclose.\n\n' +
    '2.4 These confidentiality duties continue after testing ends, until the Developer makes the information public.'],
  ['3. Feedback',
    '3.1 Feedback means bug reports, suggestions, ideas, survey answers and comments. Anything you give is voluntary.\n\n' +
    '3.2 The Developer may use, change and build on your feedback in the Game or elsewhere, forever, without ' +
    'paying or crediting you. You give the Developer all rights needed to do that, and you confirm the feedback ' +
    'is your own.'],
  ['4. Unfinished software',
    '4.1 The Game is unfinished. It may crash, lose your progress, behave unexpectedly or change completely. ' +
    'Saves may be wiped between builds.\n\n' +
    '4.2 The Game is provided "as is", without warranties of any kind, to the fullest extent the law allows. You ' +
    'play at your own risk and should back up anything important on your device.\n\n' +
    '4.3 To the fullest extent the law allows, the Developer isn\'t liable for any loss or damage arising from ' +
    'the Game or this test. Nothing here limits liability that can\'t be limited by law.'],
  ['5. Your information',
    '5.1 The sign-up and feedback forms collect your name, email, age range, country, device details and your ' +
    'answers. Multiplayer connects through Steam (your Steam name and ID) or your local network.\n\n' +
    '5.2 This information is used only to run the test, contact you about it, and improve the Game. It isn\'t ' +
    'sold. You can ask for it to be deleted at any time.'],
  ['6. Age',
    '6.1 You must be at least 13 to take part. If you\'re under 18, a parent or guardian must also accept this ' +
    'agreement on this form. They\'re responsible for your use of the Game.'],
  ['7. Ending the test',
    '7.1 You can stop testing at any time. The Developer can end your access at any time, for any reason.\n\n' +
    '7.2 When testing ends, or if the Developer asks, you must delete every build of the Game you have.\n\n' +
    '7.3 Sections 1.3, 2, 3, 4 and 8 continue after testing ends.'],
  ['8. General',
    '8.1 Testing is voluntary and unpaid. It doesn\'t make you an employee, partner or contractor of the Developer.\n\n' +
    '8.2 This is the whole agreement about the test. If a part of it can\'t be enforced, the rest still applies.\n\n' +
    '8.3 This agreement is governed by the laws of ' + GOVERNING_LAW + '.\n\n' +
    '8.4 Questions or permission requests: ' + CONTACT + '.'],
];


function createTesterForms() {
  var signup = createSignupForm_();
  var feedback = createFeedbackForm_();
  Logger.log('SIGN-UP & AGREEMENT');
  Logger.log('  Send testers:  ' + signup.form.getPublishedUrl());
  Logger.log('  Edit form:     ' + signup.form.getEditUrl());
  Logger.log('  Responses:     ' + signup.sheet.getUrl());
  Logger.log('FEEDBACK SURVEY');
  Logger.log('  Send testers:  ' + feedback.form.getPublishedUrl());
  Logger.log('  Edit form:     ' + feedback.form.getEditUrl());
  Logger.log('  Responses:     ' + feedback.sheet.getUrl());
}


function createSignupForm_() {
  var form = FormApp.create(GAME + ' - Tester Sign-up & Agreement');
  form.setDescription(
    'Thanks for helping test ' + GAME + '! Fill this in and accept the Beta Tester Agreement before you get a ' +
    'build. It takes about 5 minutes. Questions: ' + CONTACT + '.');
  collectVerifiedEmails_(form);
  form.setLimitOneResponsePerUser(true);
  form.setProgressBar(true);
  form.setConfirmationMessage(
    'You\'re signed up. You\'ll get the build and tester instructions by email. Remember: keep everything about ' +
    'the game private until it\'s announced. (Under 13s can\'t join the test yet. Sorry!)');

  // Page 1: about you.
  form.addTextItem().setTitle('Full name').setRequired(true);
  form.addTextItem().setTitle('Discord or Steam username')
    .setHelpText('So we can add you to the tester group and play multiplayer with you.');
  form.addTextItem().setTitle('Country').setRequired(true);
  form.addCheckboxItem().setTitle('What will you play on?')
    .setChoiceValues(['Windows PC', 'Mac', 'Linux', 'Steam Deck', 'iPhone / iPad', 'Android']).setRequired(true);
  form.addParagraphTextItem().setTitle('Computer specs (optional)')
    .setHelpText('Graphics card, processor and memory if you know them. Helps us track down performance problems.');
  var age = form.addMultipleChoiceItem().setTitle('How old are you?').setRequired(true);

  // Page 2: parent or guardian (13-17 only).
  var guardianPage = form.addPageBreakItem().setTitle('Parent or guardian')
    .setHelpText('Because the tester is under 18, a parent or guardian needs to read the agreement on the next ' +
                 'page and fill this in.');
  form.addTextItem().setTitle('Parent or guardian\'s full name').setRequired(true);
  form.addTextItem().setTitle('Relationship to the tester').setRequired(true);
  form.addTextItem().setTitle('Parent or guardian\'s email').setRequired(true)
    .setValidation(FormApp.createTextValidation().requireTextIsEmail().build());
  form.addCheckboxItem().setTitle('Parent or guardian consent')
    .setChoiceValues(['I am the tester\'s parent or guardian. I have read the Beta Tester Agreement on the next ' +
                      'page, I agree to it on their behalf, and I accept responsibility for their use of the game.'])
    .setRequired(true);

  // Page 3: the agreement.
  var agreementPage = form.addPageBreakItem().setTitle('Beta Tester Agreement (EULA + NDA)')
    .setHelpText('Please read all of it. A copy is kept with your response.');
  AGREEMENT.forEach(function (section) {
    form.addSectionHeaderItem().setTitle(section[0]).setHelpText(section[1]);
  });
  var promises = [
    'I have read and agree to the Beta Tester Agreement.',
    'I will keep the game confidential: no streaming, screenshots, videos or posts without permission.',
    'I will not share the build with anyone, and I will delete it when asked.',
  ];
  form.addCheckboxItem().setTitle('I agree').setChoiceValues(promises).setRequired(true)
    .setValidation(FormApp.createCheckboxValidation().requireSelectAtLeast(promises.length)
      .setHelpText('Please tick all three to take part.').build());
  form.addTextItem().setTitle('Signature: type your full name').setRequired(true)
    .setHelpText('Typing your name here counts as signing the agreement.');
  form.addDateItem().setTitle('Date').setRequired(true);

  // 18+ skips the guardian page; under 13 submits straight away.
  age.setChoices([
    age.createChoice('18 or older', agreementPage),
    age.createChoice('13 to 17 (a parent or guardian must agree too)', guardianPage),
    age.createChoice('Under 13', FormApp.PageNavigationType.SUBMIT),
  ]);

  return {form: form, sheet: linkSheet_(form)};
}


function createFeedbackForm_() {
  var form = FormApp.create(GAME + ' - Tester Feedback');
  form.setDescription(
    'Tell us how this build played. Fill it in once per build you test. Honest is best: what\'s boring or ' +
    'broken is the most useful thing you can tell us. About 5-10 minutes.');
  collectVerifiedEmails_(form);
  form.setProgressBar(true);
  form.setConfirmationMessage('Thanks! Every answer gets read.');

  // Page 1: your session.
  form.addTextItem().setTitle('Which build did you play?')
    .setHelpText('The version or date of the build, if you know it.');
  form.addMultipleChoiceItem().setTitle('How long did you play this build?').setRequired(true)
    .setChoiceValues(['Under 30 minutes', '30 minutes to 2 hours', '2 to 5 hours', '5 to 10 hours', 'Over 10 hours']);
  form.addTextItem().setTitle('What company level did you reach?');
  form.addMultipleChoiceItem().setTitle('What did you play on?').setRequired(true)
    .setChoiceValues(['Windows PC', 'Mac', 'Linux', 'Steam Deck']).showOtherOption(true);
  form.addMultipleChoiceItem().setTitle('Did you play multiplayer?').setRequired(true)
    .setChoiceValues(['Yes, over Steam', 'Yes, on a local network (LAN)', 'No']);

  // Page 2: how it felt.
  form.addPageBreakItem().setTitle('How it felt');
  form.addScaleItem().setTitle('Overall, how fun was it?').setBounds(1, 10)
    .setLabels('Not fun', 'Couldn\'t stop').setRequired(true);
  form.addScaleItem().setTitle('How likely are you to recommend it to a friend?').setBounds(0, 10)
    .setLabels('Not at all', 'Definitely').setRequired(true);
  form.addMultipleChoiceItem().setTitle('How was the pace of progress?').setRequired(true)
    .setChoiceValues(['Much too slow', 'A bit slow', 'About right', 'A bit fast', 'Much too fast']);
  form.addGridItem().setTitle('How did you find each part of the game?')
    .setRows(['Buying and upgrading ships', 'Setting routes', 'Trading goods and markets',
              'Fuel, maintenance and repairs', 'Ports and port growth', 'HQ and hubs', 'Levels and skills',
              'Weather, storms and ice', 'Canals, convoys and icebreakers', 'Multiplayer'])
    .setColumns(['Loved it', 'Liked it', 'It\'s OK', 'Didn\'t like it', 'Didn\'t try it']);
  form.addParagraphTextItem().setTitle('What did you enjoy most?');
  form.addParagraphTextItem().setTitle('What was confusing, boring or frustrating?');

  // Page 3: bugs and performance.
  form.addPageBreakItem().setTitle('Bugs and performance');
  form.addMultipleChoiceItem().setTitle('Did the game crash or freeze?').setRequired(true)
    .setChoiceValues(['Never', 'Once', 'A few times', 'Often']);
  form.addScaleItem().setTitle('How smoothly did it run?').setBounds(1, 5)
    .setLabels('Very laggy', 'Perfectly smooth').setRequired(true);
  form.addParagraphTextItem().setTitle('Bugs you found')
    .setHelpText('For each one: what happened, what you were doing just before, and whether you can make it ' +
                 'happen again.');
  form.addParagraphTextItem().setTitle('Multiplayer problems (if you played it)')
    .setHelpText('Trouble joining, lag, things out of sync between players...');

  // Page 4: the bigger picture.
  form.addPageBreakItem().setTitle('The bigger picture');
  form.addMultipleChoiceItem().setTitle('Would you buy this game on Steam?').setRequired(true)
    .setChoiceValues(['Definitely', 'Probably', 'Not sure', 'Probably not', 'No']);
  form.addMultipleChoiceItem().setTitle('What feels like a fair price?')
    .setChoiceValues(['It should be free to play', 'Under $5', '$5-10', '$10-15', '$15-20', '$20-30', 'Over $30']);
  form.addParagraphTextItem().setTitle('If you could change or add one thing, what would it be?');
  form.addParagraphTextItem().setTitle('Anything else?');
  form.addMultipleChoiceItem().setTitle('Can we contact you with follow-up questions?')
    .setChoiceValues(['Yes', 'No']);

  return {form: form, sheet: linkSheet_(form)};
}


/** Testers sign in with Google, so every response comes with a verified email. */
function collectVerifiedEmails_(form) {
  try {
    form.setEmailCollectionType(FormApp.EmailCollectionType.VERIFIED);
  } catch (e) {
    form.setCollectEmail(true);
  }
}


/** A new Google Sheet next to the form that collects its responses. */
function linkSheet_(form) {
  var sheet = SpreadsheetApp.create(form.getTitle() + ' (Responses)');
  form.setDestination(FormApp.DestinationType.SPREADSHEET, sheet.getId());
  return sheet;
}

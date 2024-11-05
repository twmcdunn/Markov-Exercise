//set this to match the sample rate of your speakers
s.options.sampleRate = 44100;

//run this block to initialize things (the orchestra)
(
s.reboot;
s.waitForBoot({
	//starts sending mouseY values to the client machine
	{SendReply.kr(Impulse.kr(4), '/reply', MouseY.kr(),-1)}.play;

	//sample (must be in the same directory as this patch)
	~b = Buffer.read(s, thisProcess.nowExecutingPath.dirname +/+ "7.wav");
	//original frequency of sample
	~origFreq = 1760;

	/*
	* in each stratum: 0 - mouse does note control dynamics
	* 1 - mouse does control dynamics
	*/
	~mouseDynamics = [0,0,0,0,0,0];

	/*
	* in each stratum default amp if not controled by mouse
	*/
	~amp = [0.5,0.5,0.5,0.5,0.5,0.5];
	~curAmp = [0.5,0.5,0.5,0.5,0.5,0.5];//used to create lag (gradual dynamic change)

	//don't worry about the synths
	SynthDef(\ln, {
		arg out;
		Out.kr(out, LFNoise2.ar(1 / 3.0));
	}).add;

	SynthDef(\sampleSynth, {
		arg freq, voice = 0, amp, mouseDynamics;
		var sig;
		amp = 0.25 * SelectX.kr(mouseDynamics, [amp, MouseX.kr()]);//no varlag
		sig = amp * PlayBuf.ar(1,~b,BufRateScale.kr(~b) * freq / ~origFreq, doneAction: Done.freeSelf);
		sig = BLowPass4.ar(sig,20000 * (In.kr(6 + (1 + voice) % 6) + 1) / 2);
		Out.ar(4,Pan2.ar(sig, In.kr(6 + voice)));
	}).add;

	SynthDef(\rev, {
		//arg mix = 0.5, room = 0.7, damp = 0.5;
		var sig;
		sig = In.ar(4,2);
		sig = FreeVerb2.ar(sig[0],sig[1],\mix.kr(0.5,2),\room.kr(0.7,2),\damp.kr(0.5,2));
		Out.ar(0,sig);
	}).add;

	SynthDef(\filter, {
		var sig;
		sig = In.ar(4,2);
		sig = BLowPass4.ar(sig, 0 + 20000 * (LFNoise2.kr(1 / 3.0) + 1) / 2);
		Out.ar(0,sig);
	}).add;


	/*C Major scale in numbers (c = 0).
	* Includes top note.
	*/
	~scale = [0,2,4,5,7,9,11,12];

	/*Transition Probabilities Matrix
	It's 8 x 8 because there are 8 notes in the scale.
	Each column represents the starting note (in order from low to high).
	Each row represents the potential next note.
	The numbers in the matrix represent the probabilities that an given
	transition will occur.
	It makes the most sense if the numbers in a given row add up to 1,
	but I normalize the numbers later just in case; if they don't add up to one,
	it won't break anything.
	*/
	~transMatrix = [
		[0.0, 0.1, 0.2, 0.1, 0.3, 0.1, 0.1, 0.1],
		[0.3, 0.0, 0.3, 0.1, 0.1, 0.1, 0.1, 0.0],
		[0.3, 0.1, 0.0, 0.1, 0.2, 0.1, 0.1, 0.1],
		[0.1, 0.0, 0.5, 0.0, 0.1, 0.2, 0.0, 0.1],
		[0.3, 0.1, 0.2, 0.1, 0.0, 0.1, 0.1, 0.2],
		[0.2, 0.0, 0.2, 0.2, 0.1, 0.0, 0.1, 0.2],
		[0.0, 0.2, 0.0, 0.0, 0.2, 0.1, 0.0, 0.5],
		[0.1, 0.1, 0.2, 0.1, 0.3, 0.1, 0.1, 0.0],
	];

	//normalize the matrix (make each row add up to 1
	~transMatrix.do({arg row, i;
		var sum = 0;
		row.do({arg prob;
			sum = prob + sum;
		});
		row.do({arg prob, n;
			row[n] = prob / sum;
		});
	});

	//gets a scale degree based on previous scale degree
	//using transitional prob. matrix
	~getNextNote = {
		arg note;
		var rnd = 1.0.rand, tot = 0, newNote;
		i = 0;
		while({tot <= rnd},{
			tot = tot + ~transMatrix[note][i];
			newNote = i;
			i = i + 1;
		});
		newNote;
	};

	/*which note of the scale each
	* stratum starts on
	*/
	~noteIndexes = [0,4,2,0,4,2];

	TempoClock.tempo = 1.0; //1 beat PER SECOND (i.e. quarter = 60

	~rhyth = [
		//rhythmic values used at rate zero (duration in beats)
		[0.1, 0.4/3.0, 0.16, 0.2],
		//rhythmic values used at rate 1 (duration in beats)
		[0.2, 0.3, 0.4],
		//rhythmic values used at rate 2 (duration in beats)
		[2 / 3.0, 0.8, 1]];

	//rate of each voice
	~stratumRate = [0,0,0,0,0,0];

	//an array that will hold the music streams
	~streams = [nil,nil,nil,nil,nil,nil];

	//Assigned values later
	~mouseY = 0;
	~mouseControlsHighestNote = false;
	~mouseControlsLowestNote = false;
	~targetHighest = 96;
	~highestNote = 96;
	~targetLowest = 24;
	~lowestNote = 24;
	~mouseControlsRhythm = false;

	6.do({arg v;
		x = Synth.new(\ln,[\out,v+6]);
		v.postln;
		~streams[v] = Pbind(
			\instrument, \sampleSynth,
			\freq, FuncStream({
				var voice = v, midi;
				~noteIndexes[voice] = ~getNextNote.value(~noteIndexes[voice]);
				midi = (~scale[~noteIndexes[voice]] + 24 + (voice * 12));

				~mouseControlsHighestNote.if({
					~targetHighest = ~mouseY * 72 + 24;
				},{
					~targetHighest = 96;
				});

				~mouseControlsLowestNote.if({
					~targetLowest = ~mouseY * 72 + 24;
				},{
					~targetLowest = 24;
				});

				(~highestNote > ~targetHighest).if({
					~highestNote = ~highestNote - 1});
				(~highestNote < ~targetHighest).if({
					~highestNote = ~highestNote + 1});
				(~lowestNote > ~targetLowest).if({
					~lowestNote = ~lowestNote - 1});
				(~lowestNote < ~targetLowest).if({
					~lowestNote = ~lowestNote + 1});

				while({midi > ~highestNote}, {
					midi = midi - 12;
				});
				while({midi < ~lowestNote}, {
					midi = midi + 12;
				});
				midi.midicps * 4.0;
			};),
			\dur, FuncStream({
				var val = ~rhyth[~stratumRate[v]].choose;
				~mouseControlsRhythm.if({
					var prob = [1 - (~mouseY - 0).abs, 1 - (~mouseY - 0.5).abs, 1 - (~mouseY - 1).abs], sum = 0, rnd = 1.0.rand, n = 0;
					prob.do({arg item, i;
						sum = sum + item;
					});
					prob.do({arg item, i;
						prob[i] = item / sum;
					});
					sum = 0;
					while({sum < rnd},
						{
							sum = sum + prob[n];
							n = n + 1;
					});
					//prob.postln;
					val = ~rhyth[~stratumRate[v]][n-1];
					//val.postln;
				});
				val;
			}),
			\voice, v,
			\amp, FuncStream({
				(~curAmp[v] > ~amp[v]).if(
					{~curAmp[v] = ~curAmp[v] * 0.9;},
					{~curAmp[v] = ~curAmp[v] * 1.1;});
				~curAmp[v];
			}),
			\mouseDynamics, FuncStream({~mouseDynamics[v]}),
			\addAction, 3,
			\group, x
		).play(quant: 1);
		~streams[v].stop;
	});
	r = Synth.tail(s, \rev);
	x = 3;
});

//Receives MouseY messages from the server
y.free;
y = OSCFunc.newMatching({ arg msg;
	~mouseY = msg[3];
}, '/reply');

)


//The score:
/*
* The patch produces 6 strata of musical textures
stratum 0: C3 - C4
stratum 1: C4 - C5
stratum 2: C5 - C6
stratum 3: C6 - C7
stratum 4: C7 - C8
stratum 5: C8 - C9

midi nums 24 - 96
*/

//These commmands start (i.e. resume) each stratum
~streams[0].resume(quant:1);
~streams[1].resume(quant:1);
~streams[2].resume(quant:1);
~streams[3].resume(quant:1);
~streams[4].resume(quant:1);
~streams[5].resume(quant:1);

//These commmands stop (i.e. pause) each stratum
~streams[0].stop;
~streams[1].stop;
~streams[2].stop;
~streams[3].stop;
~streams[4].stop;
~streams[5].stop;

//The commands below alter a given stratum x,
//replace 'x' with the number stratum you'd like
//to use.

//use these command to set the dynamics of a stratum x
//valid dynamics are 0 - 1. 0 = silence, 1 = full volume
~amp[x] = 0.1; // soft
~amp[x] = 0.5; // medium
~amp[x] = 0.9; // loud
~amp[x] = 0;//fade out to silence

//use these commands to map the dynamics of a stratum x
//to the horizontal position of your mouse. left = soft, right = loud
~mouseDynamics[x] = 1;//start mapping
~mouseDynamics[x] = 0;//stop mapping

//use these commands to change the rhythmic rate of a
//given stratum x. Valid rates are integers 0 - 2.
~stratumRate[x] = 0; // fast
~stratumRate[x] = 1; // medium
~stratumRate[x] = 2; // slow

//use these commands to change the tempo. The tempo is
//measured in beats per second, not PBM. so 2 means quarter = 120
TempoClock.tempo = 1.0; // 60 pbm
TempoClock.tempo = 2.0; // 120 pbm
TempoClock.tempo = 80/60; // 80 pbm

//use these commnands to change the scale.
// your scale isn't 8 notes (including the octave)
//you should adjust the ~transMatrix too
//the scales below don't require any change to ~transMatrix
~scale = [0,2,4,5,7,9,11,12];//major
~scale = [0,2,3,5,7,8,10,12];//natural minor
~scale = [0,2,3,5,7,9,10,12];//dorian
~scale = [0,1,3,5,7,8,10,12];//phrygian
~scale = [0,2,4,6,7,9,11,12];//lydian
~scale = [0,2,4,5,7,9,10,12];//mixolydian
~scale = [0,1,3,5,6,8,10,12];//locrian
~scale = [0,2,4,6,7,9,10,12];//acoustic

~scale = [0,1,3,4,6,7,9,10];//octotonic
~scale = [0,2,3,5,6,8,9,11];//another octotonic
~scale = [0,2,4,6,8,10,12,14];//whole tone (more than an octave, to make it 8 notes)
~scale = [0,1,4,5,8,9,12,13];//hexatonic (more than an octave, to make it 8 notes)

/*
*You can compress the range of the whole texture, using the mouse's height.
*This will set the lowest allowed note or highest allowed note. Notes out side of
*the range will be transposed by octaves.
*Use the commands below to turn this feature on and off.
*/
~mouseControlsLowestNote = true; //turns it on
~mouseControlsLowestNote = false; //turns it off
~mouseControlsHighestNote = true; //turns it on
~mouseControlsHighestNote = false; //turns it off

/*
* You can use the mouse to make small adustmest to the rhythmic denisty.
* Use these commands to turn this on and off
*/
~mouseControlsRhythm = true;
~mouseControlsRhythm = false;

/*
*You can change the transitional probabilities to vary the texture.
*Here are some examples.
*/

//Only stepwise
(
~transMatrix = [
	[0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.5, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.5, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.5, 0.0, 0.5, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.5, 0.0, 0.5, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.5, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.5],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
];
)

//Trills (more static)
(
~transMatrix = [
	[0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.95, 0.0, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.05, 0.0, 0.95, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.95, 0.0, 0.05, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.05, 0.0, 0.95, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.95, 0.0, 0.05, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.0, 0.95],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
];
)

//Thirds Trills (more static)
(
~transMatrix = [
	[0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.05, 0.0, 0.0, 0.95, 0.0, 0.0, 0.0, 0.0],
	[0.95, 0.0, 0.0, 0.05, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.95, 0.0, 0.0, 0.05, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.05, 0.0, 0.0, 0.95, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.05, 0.0, 0.0, 0.95],
	[0.0, 0.0, 0.0, 0.0, 0.95, 0.0, 0.0, 0.05],
	[0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
];
)

//default
(
~transMatrix = [
		[0.0, 0.1, 0.2, 0.1, 0.3, 0.1, 0.1, 0.1],
		[0.3, 0.0, 0.3, 0.1, 0.1, 0.1, 0.1, 0.0],
		[0.3, 0.1, 0.0, 0.1, 0.2, 0.1, 0.1, 0.1],
		[0.1, 0.0, 0.5, 0.0, 0.1, 0.2, 0.0, 0.1],
		[0.3, 0.1, 0.2, 0.1, 0.0, 0.1, 0.1, 0.2],
		[0.2, 0.0, 0.2, 0.2, 0.1, 0.0, 0.1, 0.2],
		[0.0, 0.2, 0.0, 0.0, 0.2, 0.1, 0.0, 0.5],
		[0.1, 0.1, 0.2, 0.1, 0.3, 0.1, 0.1, 0.0],
	];
)

/*
* Adjust the reverb
*/
r.set(\room, 0.7, \mix, 0.5, \damp, 0.5); // default
r.set(\mix, 0); // dry
r.set(\room, 1, \mix, 1, \damp, 1);//drench it

/*to make a cue, put several commands together, one after the other
* with an open and closed parathesis above and below respectively.
* Be sure to label your cues with a name (e.g. cue 1, cue 2, etc).
*
*In the example below, a softer, more static section begins in a new
* mode by
* adusting several parameters at once.
*/

// Cue 7
(
~streams[1].resume(quant:1);
~streams[2].resume(quant:1);
~streams[3].resume(quant:1);
~streams[4].resume(quant:1);
~streams[5].resume(quant:1);

~mouseControlsHighestNote = true;
~transMatrix = [
	[0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.95, 0.0, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.05, 0.0, 0.95, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.95, 0.0, 0.05, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.05, 0.0, 0.95, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.95, 0.0, 0.05, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.0, 0.95],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
];
~scale = [0,2,4,6,7,9,10,12];
r.set(\room, 0.7, \mix, 0.9, \damp, 0.5);
~stratumRate[5] = 1;
~stratumRate[4] = 1;
~stratumRate[3] = 0;
~stratumRate[2] = 0;
~stratumRate[1] = 0;
~amp[5] = 0.1;
~amp[4] = 0.1;
~amp[3] = 0.1;
~amp[2] = 0.1;
~amp[1] = 0.1;
~amp[0] = 0.0;
)

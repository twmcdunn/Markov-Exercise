//if you get a message about mismatch audio rate, you'll need
//to adjust your audio settings on the computer, then reboot the
//supercollider audio server

//run this block to initialize things (the orchestra)
(
s.reboot;
s.waitForBoot({
	fork{

		SystemClock.clear;//clear the transition loop
		TempoClock.all.do(_.clear);  // clear the pbinds
		s.sync;//wait for the above

		~dir = PathName(Document.current.dir +/+ "bell_1760hz.wav").fullPath;
		//starts sending mouseY values to the client machine
		{SendReply.kr(Impulse.kr(4), '/reply', MouseY.kr(),-1)}.play;

		//sample (must be in the same directory as this patch)
		~b = Buffer.read(s, ~dir);
		//original frequency of sample
		~origFreq = 1760;
		"LOADING SOUND SAMPLE".postln;
		s.sync;//allows time for buffer to finish loading (just in case)

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
			sig = FreeVerb2.ar(sig[0],sig[1],\mix.kr(0.5,2).lag(3 * \lag.kr(0.5)),\room.kr(0.7,2).lag(3 * \lag.kr(0.5)),\damp.kr(0.5,2).lag(3 * \lag.kr(0.5)));
			Out.ar(0,sig);
		}).add;

		SynthDef(\filter, {
			var sig;
			sig = In.ar(4,2);
			sig = BLowPass4.ar(sig, 0 + 20000 * (LFNoise2.kr(1 / 3.0) + 1) / 2);
			Out.ar(0,sig);
		}).add;

		"LOADING SYNTHS".postln;
		s.sync;//allows time for synths to finish loading (just in case)

		/*C Major scale in numbers (c = 0).
		* Includes top note.
		*/
		~scale = [0,2,4,5,7,9,11,12];

		//smooths out tranitions. when a new scale is set.
		//it gradually becomes more probable that the new
		//scale is used
		~lastScale = ~scale;
		~scaleProb = 1;
		~scaleTransitioning = false;

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

		//smooths out transitions. when a new ~transMatrix is set,
		//it gradually becomes more probable that the new matrix
		//is used
		~lastMatrix  = ~transMatrix;
		~matrixProb = 1;//probability of using ~transMatrix
		~matrixTransitioning = false;

		//gets a scale degree based on previous scale degree
		//using transitional prob. matrix
		~getNextNote = {
			arg note;
			var rnd = 1.0.rand, tot = 0, newNote, matrix;

			matrix = ~transMatrix;
			if(~lastMatrix != ~transMatrix){
				if(~matrixTransitioning.not){//start transitioning
					"START TRANSITIONING".postln;
					~matrixProb = 0;
					~matrixTransitioning = true;
				};
				if(1.0.rand > ~matrixProb){matrix = ~lastMatrix;};

				if(~matrixProb >= 1){
					"STOP TRANSITIONING".postln;
					~lastMatrix = ~transMatrix;
					~matrixTransitioning = false;
				};//stop transitioning
			};

			i = 0;
			if(note > (matrix.size - 1)){note = matrix.size.rand};//if the matrix changed sizes, pick a random row

			while({tot <= rnd},{
				if(i < matrix[note].size){
					tot = tot + matrix[note][i];
					newNote = i;
					i = i + 1;
				}
				{
					tot = rnd;
					newNote = matrix.size.rand;
				};
			});
			newNote;
		};

		/*
		smooth out tempo changes
		*/
		~bpm = 60;
		~curBpm = 60;

		~transitionLoop = {
			if(~matrixProb < 1){~matrixProb = ~matrixProb + 0.01};
			if(~scaleProb < 1){~scaleProb = ~scaleProb + 0.01};
			if(~transpoProb < 1){~transpoProb = ~transpoProb + 0.01};

			6.do{|v|
				if(~curAmp[v] > ~amp[v]){
					if((~curAmp[v] < 0.001) && (~amp[v] == 0))
					{~curAmp[v] = 0}
					{~curAmp[v] = ~curAmp[v] * 0.95};
				};
				if(~curAmp[v] < ~amp[v]){
					if((~curAmp[v] == 0) && (~amp[v] > 0))
					{~curAmp[v] = 0.01}
					{~curAmp[v] = ~curAmp[v] * 1.05;};
				};
			};
			if(~curBpm < ~bpm){~curBpm = ~curBpm + 1};
			if(~curBpm > ~bpm){~curBpm = ~curBpm - 1};
			TempoClock.tempo = ~curBpm / 60;
			/*(~highestNote > ~targetHighest).if({
				~highestNote = ~highestNote - 1});
			(~highestNote < ~targetHighest).if({
				~highestNote = ~highestNote + 1});
			(~lowestNote > ~targetLowest).if({
				~lowestNote = ~lowestNote - 1});
			(~lowestNote < ~targetLowest).if({
				~lowestNote = ~lowestNote + 1});*/
			if(~mouseControlsHighestNote.not){//gradually transition to target if not using mouse
				if(~curHighest < ~highestNote){~curHighest = ~curHighest + 1};
				if(~curHighest > ~highestNote){~curHighest = ~curHighest - 1};
			};

			if(~mouseControlsLowestNote.not){
				if(~curLowest < ~lowestNote){~curLowest = ~curLowest + 1};
				if(~curLowest > ~lowestNote){~curLowest = ~curLowest - 1};
			};
		};

		~transitionSpeed = 0.5;
		~transitionClock = Routine{
			loop{
				~transitionLoop.();
				// ("UPDATING "++Main.elapsedTime).postln;
				((((1 - ~transitionSpeed)) * 0.1) + 0.0001).wait;
			};
		}.play(SystemClock);

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
		~strata = [nil,nil,nil,nil,nil,nil];

		//Assigned values later
		~mouseY = 0;
		~mouseControlsHighestNote = false;
		~mouseControlsLowestNote = false;
		~curHighest = 96;
		~highestNote = 96;
		~curLowest = 24;
		~lowestNote = 24;
		~mouseControlsRhythm = false;
		~transpo = 0;
		~lastTranspo = 0;
		~transpoTransitioning = false;
		~transpoProb = 0;

		6.do({arg v;
			x = Synth.new(\ln,[\out,v+6]);
			//v.postln;
			~strata[v] = Pbind(
				\instrument, \sampleSynth,
				\freq, FuncStream({
					var voice = v, midi, scale, transpo;

					scale = ~scale;
					if(~lastScale != ~scale){
						if(~scaleTransitioning.not){//start transitioning
							"START TRANSITIONING".postln;
							~scaleProb = 0;
							~scaleTransitioning = true;
						};
						if(1.0.rand > ~scaleProb){scale = ~lastScale;};

						if(~scaleProb >= 1){
							"STOP TRANSITIONING".postln;
							~lastScale = ~scale;
							~scaleTransitioning = false;
						};//stop transitioning
					};

					transpo = ~transpo;
					if(~lastTranspo != ~transpo){
						if(~transpoTransitioning.not){//start transitioning
							"START TRANSITIONING".postln;
							~transpoProb = 0;
							~transpoTransitioning = true;
						};
						if(1.0.rand > ~transpoProb){transpo = ~lastTranspo;};

						if(~transpoProb >= 1){
							"STOP TRANSITIONING".postln;
							~lastTranspo = ~transpo;
							~transpoTransitioning = false;
						};//stop transitioning
					};

					~noteIndexes[voice] = ~getNextNote.value(~noteIndexes[voice]);
					midi = (((scale[~noteIndexes[voice] % scale.size] + transpo) % 12) + 24 + (voice * 12));

					~mouseControlsHighestNote.if({
						~curHighest = ~mouseY * 72 + 24;
					},{
						// ~targetHighest = 96;
					});

					~mouseControlsLowestNote.if({
						~curLowest = ~mouseY * 72 + 24;
					},{
							// ~targetLowest = 24;
					});

					while({midi > ~curHighest}, {
						midi = midi - 12;
					});
					while({midi < ~curLowest}, {
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
					~curAmp[v];
				}),
				\mouseDynamics, FuncStream({~mouseDynamics[v]}),
				\addAction, 3,
				\group, x
			).play(quant: 1);
			~strata[v].stop;
		});
		r = Synth.tail(s, \rev);
		x = 3;

		//Receives MouseY messages from the server
		y.free;
		y = OSCFunc.newMatching({ arg msg;
			~mouseY = msg[3];
		}, '/reply');

		"EVERYTHING IS READY TO PLAY!".postln;
	}
});
)

//Ctl/Cmd + . to stop all sound (need to execute the orchestra block again to restart)

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
~strata[0].resume(quant:1);
~strata[1].resume(quant:1);
~strata[2].resume(quant:1);
~strata[3].resume(quant:1);
~strata[4].resume(quant:1);
~strata[5].resume(quant:1);

//These commmands stop (i.e. pause) each stratum
~strata[0].stop;
~strata[1].stop;
~strata[2].stop;
~strata[3].stop;
~strata[4].stop;
~strata[5].stop;

//The commands below alter a given stratum x,
//replace 'x' with the number stratum you'd like
//to use.

//use these command to set the dynamics of a stratum x
//valid dynamics are 0 - 1. 0 = silence, 1 = full volume
~amp[x] = 0.1; // soft
~amp[x] = 0.5; // medium
~amp[x] = 0.9; // loud
~amp[x] = 0;//fade out to silence

//By the way, to control a parameter for all 6 strata at once, put your command within a loop:
6.do({arg i; ~amp[i] = 0});//fades everything to 0 (silence)
6.do({arg i; ~amp[i] = 1});//fades everything to 1 (maximum loudness)
6.do({arg i; ~strata[i].resume(quant: 1)});//starts all stata
6.do({arg i; ~strata[i].stop});//stops all stata

//use these commands to map the dynamics of a stratum x
//to the horizontal position of your mouse. left = soft, right = loud
~mouseDynamics[x] = 1;//start mapping
~mouseDynamics[x] = 0;//stop mapping
//map all strata
6.do({arg i; ~mouseDynamics[i] = 1});//start mapping
6.do({arg i; ~mouseDynamics[i] = 0});//stop mapping

//use these commands to change the rhythmic rate of a
//given stratum x. Valid rates are integers 0 - 2.
~stratumRate[x] = 0; // fast
~stratumRate[x] = 1; // medium
~stratumRate[x] = 2; // slow

//use these commands to change the tempo. gradual retard / accel
~bpm = 120;
~bpm = 80;
~bpm = 60;

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
~scale = [0,2,4,6,8,10,12];//whole tone (more than an octave, to make it 8 notes)
~scale = [0,1,4,5,8,9,12,13];//hexatonic (more than an octave, to make it 8 notes)

/*
You can also change the "tonic note" or "transposition" of
the scale
*/
~transpo = 6;//F# is tonic
~transpo = 0;//C is tonic (default)

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
You can also manually control the highest or lowest note
if mouse control is false. The patch will smoothly
transition to the value you set.
*/
~highestNote = 60;//middle c
~highestNote = 96;//C7 (default)
~lowestNote = 55; //G3
~lowestNote = 24;//C1 (default)

/*
*You can change the transitional probabilities to vary the texture.
*Here are some examples. The patch will smoothly transition to the
*new matrix.
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
r.set(\room, 0.7, \mix, 0.5, \damp, 0.5, \lag, 1 - ~transitionSpeed); // default
r.set(\mix, 0, \lag, 1 - ~transitionSpeed); // dry
r.set(\room, 1, \mix, 1, \damp, 1, \lag, 1 - ~transitionSpeed);//drench it

/*
Change how quicly the patch transitions from one setting to another.
This affects the rate at which
     - amplitude
     - lowest note
     - highest note
     - scale
     - transition probability matrix
     - reverb
change when a new value is set.
*/
~transitionSpeed = 0;//fade very gradually
~transitionSpeed = 1;//change almost instantly
~transitionSpeed = 0.5;//default

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
~strata[1].resume(quant:1);
~strata[2].resume(quant:1);
~strata[3].resume(quant:1);
~strata[4].resume(quant:1);
~strata[5].resume(quant:1);

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


// To play a midi mockup or other sound file alongside your markov patch,
// put the sound file in the same folder as this patch and run this.
// set the fileName variable to the name of your file and set stereo
// to false (all lower case, no quotes) if your file is mono (right
// click the file and check its properties / info).
// To start the sound part way through set startTime to the number of
// seconds in that you want to start.
(
{
	var fileName = "YOUR FILE NAME IN QUOTES.wav",//any standard sound format, include extension, but not path
	stereo = true,//set to false for mono files
	startTime = 0,//number of seconds in to start

	dir = PathName(Document.current.dir +/+ fileName).fullPath,
	buff = Buffer.read(s, dir, action: {
		~mockupSound = {
			var sig, chan = 1;
			if(stereo){chan = 2};
			sig = PlayBuf.ar(chan, buff, BufRateScale.kr(buff), startPos: startTime * buff.sampleRate);
			if(stereo.not){sig = sig.dup};
			sig;
		}.play;
	});
}.value;
)

//To stop the sound after running the above:
~mockupSound.free;

//record your markov exercise (overwite file if it already exists)
s.record(path:PathName(Document.current.dir +/+ "myExercise.wav").fullPath);
// Ctl/Cmd + . to stop all sound and end recording (need to execute
// the orchestra block again to restart)




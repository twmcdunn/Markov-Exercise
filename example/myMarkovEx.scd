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

		~noScaleTransition = false;
		~scaleJump = Routine{
			loop{
				if(~noScaleTransition){~scaleProb = 1};
				0.0001.wait;
			}
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
		s.sync;

		~saturation = false;
		~delay = true;
		~flanger = false;
		~harmonizer = false;
		~sweep = false;
		~fx = {
			|sig|
			var dry;
			sig = Mix.ar(sig);
			dry = sig;
			if(~saturation){
				sig = (sig * 10).distort;
				sig = sig / 10;
			};

	/*if(~flanger){
		var mod;
		mod = SinOsc.kr(1/5.0).range(0.01,0.011);
		3.do{sig = CombC.ar(sig, 0.01, mod, 0.1)};
	};*/
			if(~flanger){
				var mod;
				mod = SinOsc.kr(1/5.0).range(0.005, 0.01);
				sig = AllpassC.ar(sig, 0.01, mod, 0.1) + sig;  // Mix with original
				sig = sig * 0.5;  // Compensate for level
			};
			if(~delay){
				3.do{
					var del = 0.5 + 3.rand;
					sig = CombC.ar(sig, del, del,3);
				};
				sig = sig / 3;
			};
			if(~sweep){
				var mod;
				mod = SinOsc.kr(1/4.0).range(1000,10000);
				sig = LPF.ar(sig, mod);
			};
			if(~harmonizer){
				sig = Mix.ar([1,3,5].collect{|harm| PitchShift.ar(sig, pitchRatio: harm) / harm});
			};
			// Mix.ar(sig, dry);
			sig.dup;
		};


		// To play a midi mockup or other sound file alongside your markov patch,
		// put the sound file in the same folder as this patch and run this.
		// set the fileName variable to the name of your file and set stereo
		// to false (all lower case, no quotes) if your file is mono (right
		// click the file and check its properties / info).
		// To start the sound part way through set startTime to the number of
		// seconds in that you want to start.

		~playEwi = {
			var fileName = "ewi sound1.wav",//any standard sound format, include extension, but not path
			stereo = true,//set to false for mono files
			startTime = 0,//number of seconds in to start

			dir = PathName(Document.current.dir +/+ fileName).fullPath,
			buff = Buffer.read(s, dir, action: {
				~mockupSound = {
					var sig, chan = 1;
					if(stereo){chan = 2};
					sig = PlayBuf.ar(chan, buff, BufRateScale.kr(buff), startPos: startTime * buff.sampleRate);
					if(stereo.not){sig = sig.dup};
					sig = ~fx.(sig);
					sig;
				}.play;
			});
		};



		// s.record(path:PathName(Document.current.dir +/+ "myExercise.wav").fullPath);

		~transitionSpeed = 1;//so these are set right away
		~noScaleTransition = false;
		~bpm = 60;
		6.do({arg i; ~amp[i] = 0});
		~pent = [0,2,4,7,9,12];
		~wtPent = [0,2,4,6,9,12];
		~transpo = 0;
		~scale = ~pent;
		~soak = {r.set(\room, 1, \mix, 1, \damp, 1, \lag, 1 - ~transitionSpeed)};
		~normRev = {r.set(\room, 0.7, \mix, 0.5, \damp, 0.5, \lag, 1 - ~transitionSpeed)};
		~normRev.();
		~stepwise = [
			[0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
			[0.5, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0],
			[0.0, 0.5, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0],
			[0.0, 0.0, 0.5, 0.0, 0.5, 0.0, 0.0, 0.0],
			[0.0, 0.0, 0.0, 0.5, 0.0, 0.5, 0.0, 0.0],
			[0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.5, 0.0],
			[0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.5],
			[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
		];

		~trills = [
			[0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
			[0.95, 0.0, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0],
			[0.0, 0.05, 0.0, 0.95, 0.0, 0.0, 0.0, 0.0],
			[0.0, 0.0, 0.95, 0.0, 0.05, 0.0, 0.0, 0.0],
			[0.0, 0.0, 0.0, 0.05, 0.0, 0.95, 0.0, 0.0],
			[0.0, 0.0, 0.0, 0.0, 0.95, 0.0, 0.05, 0.0],
			[0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.0, 0.95],
			[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
		];

		~default =  [
			[0.0, 0.1, 0.2, 0.1, 0.3, 0.1, 0.1, 0.1],
			[0.3, 0.0, 0.3, 0.1, 0.1, 0.1, 0.1, 0.0],
			[0.3, 0.1, 0.0, 0.1, 0.2, 0.1, 0.1, 0.1],
			[0.1, 0.0, 0.5, 0.0, 0.1, 0.2, 0.0, 0.1],
			[0.3, 0.1, 0.2, 0.1, 0.0, 0.1, 0.1, 0.2],
			[0.2, 0.0, 0.2, 0.2, 0.1, 0.0, 0.1, 0.2],
			[0.0, 0.2, 0.0, 0.0, 0.2, 0.1, 0.0, 0.5],
			[0.1, 0.1, 0.2, 0.1, 0.3, 0.1, 0.1, 0.0],
		];
	}
});
)


//cue 1
(
~transitionSpeed = 0;
~strata[4].resume(quant:1);
~amp[4] = 0.5;
)

//cue 2
(
~strata[1].resume(quant:1);
~amp[1] = 0.5;
)

//cue 3
(
~strata[3].resume(quant:1);
~amp[3] = 0.5;
)

//cue 4
(
~strata[0].resume(quant:1);
~strata[2].resume(quant:1);
~amp[0] = 0.5;
~amp[2] = 0.5;
~playEwi.value;
)

//cue 5
(
~transitionSpeed = 0.5;
~transpo = 0;
~scale = ~wtPent;
6.do({arg i; ~amp[i] = 1});
~bpm = 240;
)

//cue 6
(
~transitionSpeed = 0.5;
~transpo = 2;
~scale = ~pent;
6.do({arg i; ~amp[i] = 0.5});
~bpm = 80;
)

//cue 7 (3 x 5 on F#)
(
~transitionSpeed = 0.5;
~transpo = 6;
~scale = ~pent;
// 6.do({arg i; ~amp[i] = 1});
~bpm = 240;
~transMatrix = ~stepwise;
)

//cue 8 (3 x 5 on B)
(
~noScaleTransition = true;
~transitionSpeed = 0.5;
~transpo = 4;
~scale = ~wtPent;
6.do({arg i; ~amp[i] = 0.5});
~bpm = 80;
~transMatrix = ~default;
~highestNote = 82;
)

//cue 9
(
~noScaleTransition = true;
~transitionSpeed = 0.5;
~transpo = 4;
~scale = ~pent;
6.do({arg i; ~amp[i] = 0.5});
~bpm = 80;
~highestNote = 60;
)

//cue 10 (3 x 5 on Bb)
(
~noScaleTransition = true;
~transitionSpeed = 0;
~transpo = 8;
~scale = ~pent;
6.do({arg i; ~amp[i] = 1});
~bpm = 240;
~transMatrix = ~trills;
~highestNote = 96;
)

//cue 11
(
~noScaleTransition = false;
~transitionSpeed = 0;
~transpo = 6;
~scale = ~wtPent;
6.do({arg i; ~amp[i] = 0.5});
~bpm = 80;
~soak.();
)

//cue 12
(
~noScaleTransition = false;
~transitionSpeed = 0;
~transpo = 6;
~scale = ~pent;
~bpm = 80;
~normRev.();
~transMatrix = ~default;
~lowestNote = 60;
)

//cue 13 (home)
(
~noScaleTransition = true;
~transitionSpeed = 0.5;
~transpo = 0;
~scale = ~pent;
~bpm = 80;
~lowestNote = 24;
)

//cue 14
(
~noScaleTransition = false;
~transitionSpeed = 0.5;
~transpo = 0;
~scale = ~wtPent;
6.do({arg i; ~amp[i] = 0.5});
~bpm = 240;
~soak.();
)

//cue 15
(
~transitionSpeed = 0.5;
~transpo = 2;
~scale = ~pent;
6.do({arg i; ~amp[i] = 0.5});
~bpm = 80;
~normRev.();
)

//cue 16
(
~transitionSpeed = 0;
~bpm = 30;
)

//cue 17
(
6.do({arg i; ~amp[i] = 0});
)

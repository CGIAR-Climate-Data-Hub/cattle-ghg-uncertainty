# -*- coding: utf-8 -*-
"""
Session 3 deck: all slide text and speaker notes.

Layout code lives in build/03_deck.py and never contains wording. Revise the
words here; rebuild; the geometry is untouched.

House rules for this file:
  * No em dashes anywhere, including speaker notes. Use commas, colons or
    parentheses. En dashes inside numeric ranges are fine.
  * Never write "Gaussian copula". The engine uses Iman-Conover restricted
    pairing on Spearman rank correlations; the copula was removed in 2026-05.
  * The correlation preset is "structural defaults, expert-elicited". IPCC
    publishes no numerical livestock correlations, so it must never be called
    IPCC-published.
  * No MCMC vocabulary: no chains, no warm-up, no burn-in, no Gelman-Rubin.
    This is independent Monte Carlo.

Every number below comes from a real 10,000-iteration run of the app on the
built-in Country X example, seed 42, AR5, no correlations unless stated.
Regenerate with build/00_simdata.R if the example data ever changes.
"""

# --------------------------------------------------------------- the real run
RUN = {
    "n_iter": "10,000",
    "seed": "42",
    "mean": "1,221,061",
    "ci_lo": "955,352",
    "ci_hi": "1,551,187",
    "moe": "24.4",
    "lower_pct": "21.8",
    "upper_pct": "27.0",
    "moe_corr": "26.4",
    "corr_widening": "8",
}

DECK_TITLE = "Monte Carlo simulation, explained gently"
DECK_SUBTITLE = "How the tool turns input ranges into a confidence interval"

# ---------------------------------------------------------------------------
# Each slide: layout + fields consumed by build/03_deck.py.
# "notes" is the speaker script. It is what you say, not a repeat of the slide.
# ---------------------------------------------------------------------------

SLIDES = [

# ====================================================== A. OPENING (3 slides)
{
    "layout": "title",
    "title": DECK_TITLE,
    "subtitle": DECK_SUBTITLE,
    "meta": "Session 3  ·  Day 1 afternoon  ·  Cattle GHG Uncertainty Tool workshop",
    "notes": (
        "Welcome back. This session has one job: by the time we break, you "
        "should be able to explain to your own inventory agency where the plus "
        "or minus on your reported total comes from, and why the method behind "
        "it is the right one to use.\n\n"
        "I am going to go slowly. There is no statistics background assumed "
        "here, and if anything is unclear please stop me, because everything "
        "after it depends on it."
    ),
},
{
    "layout": "statement",
    "kicker": "Before we start",
    "title": "You have already seen Monte Carlo results.",
    "body": [
        "The uncertainty analysis in your inventory report was a Monte Carlo simulation.",
        "@Risk is a Monte Carlo package.",
        "This session opens that box.",
    ],
    "notes": (
        "This is the most important slide for setting the level.\n\n"
        "Neither of you is meeting this method for the first time today. The "
        "uncertainty numbers that went into your inventory reports in 2023 and "
        "2024 came out of @Risk, and @Risk is a Monte Carlo package. Kola, the "
        "revised Zambia analysis earlier this year was the same method again.\n\n"
        "So what we are doing today is not learning a new technique. It is "
        "opening a box that has already been handed to you, so that you can "
        "run it yourselves and defend it to somebody else. The tool you will "
        "use tomorrow runs the same kind of engine, with the IPCC cattle "
        "equations already built in.\n\n"
        "Say this out loud, because it changes how people listen for the next "
        "hour: you are not beginners at this, you have just never been shown "
        "the inside."
    ),
},
{
    "layout": "cards",
    "title": "Three questions, and then we run it",
    "cards": [
        {"num": "1", "head": "Where does a range come from?",
         "body": "Every input in your inventory is an estimate. What does it mean to say a number is 30 plus or minus 5?"},
        {"num": "2", "head": "How do ranges combine?",
         "body": "You have around twenty-five uncertain inputs. How do their ranges add up into one range on the total?"},
        {"num": "3", "head": "Why is the answer a picture?",
         "body": "Monte Carlo does not return a number. It returns a shape, and the shape tells you more than a number could."},
    ],
    "notes": (
        "Question two is the hard one and it is where most of the session goes. "
        "Question one we touched on this morning when we looked at how the "
        "uncertainty input values were derived. Question three is where the "
        "method starts paying you back.\n\n"
        "Keep question two in your head. If you take one thing away today, it "
        "should be the answer to question two."
    ),
},

# ======================================= B. WHY ONE NUMBER IS NOT ENOUGH (4)
{
    "layout": "big_number",
    "kicker": "Your inventory today",
    "number": "1,221,061",
    "unit": "tonnes CO2 equivalent",
    "caption": "Country X, the hypothetical example built into the tool",
    "notes": (
        "Here is a number. It is the total for the Country X example that ships "
        "with the tool, and we will use that example all afternoon so nobody has "
        "to defend their own figures while they are learning.\n\n"
        "Look how confident it is. Seven digits. Down to the single tonne.\n\n"
        "Ask the room: how many of those seven digits do you actually believe? "
        "Let them answer. The honest answer is about two."
    ),
},
{
    "layout": "chain",
    "title": "But every input was itself an estimate",
    "caption": "A Tier 2 cattle inventory has around twenty-five uncertain inputs. These are six of them.",
    "notes": (
        "That seven-digit number was not measured. It was calculated, from "
        "inputs, and every single one of those inputs is itself an estimate "
        "with a range around it.\n\n"
        "Population comes from a census or a projection. Body weight comes from "
        "a survey of a few hundred animals, or from an IPCC default. "
        "Digestibility comes from feed analysis on a sample. The methane "
        "conversion factor is an IPCC coefficient with a published range.\n\n"
        "This is exactly what we were looking at this morning when we went "
        "through how each uncertainty value was derived. Point back to that "
        "session. Nothing here is new information: what is new is the question "
        "of what to do with it.\n\n"
        "None of this means the inventory is bad. It means the inventory has a "
        "width, and the width is reportable information."
    ),
},
{
    "layout": "number_line",
    "title": "So the reportable answer is a range",
    "caption": "IPCC Table 3.3 asks for the half-width of the 95% interval, as a percentage of the mean.",
    "notes": (
        "This is the convention, and it is worth being precise because it is "
        "what the reporting table actually asks for.\n\n"
        "Take a simple case. Suppose a category's emissions are 100 kilotonnes "
        "and the 95% confidence interval runs from 80 to 120. The interval is "
        "40 wide. Half of that is 20. As a percentage of the mean of 100, that "
        "is 20%. So you report 20%.\n\n"
        "That number has a name: the margin of error. You will see it written "
        "MoE all over the tool, and it is the headline metric everywhere in the "
        "app because it is the one Table 3.3 wants.\n\n"
        "One warning, because it catches people. This is not the coefficient of "
        "variation. CV is the standard deviation over the mean, it is a "
        "different number, and Table 3.3 does not ask for it. If a reviewer "
        "asks you for the CV, they are asking for something else."
    ),
},
{
    "layout": "cards",
    "title": "Three tempting answers, all wrong",
    "cards": [
        {"num": "✗", "head": "Add the percentages",
         "body": "Ten percent here, twenty percent there, so thirty percent overall. This overstates the uncertainty, usually badly.", "bad": True},
        {"num": "✗", "head": "Take the worst case",
         "body": "Set every input to its worst value at once. Ask yourself how likely it is that twenty-five independent things all go wrong together.", "bad": True},
        {"num": "✗", "head": "Report no range at all",
         "body": "Defensible only if nobody ever asks. UNFCCC reporting asks.", "bad": True},
    ],
    "notes": (
        "Spend a moment on the middle one, because it is the most seductive and "
        "the most instructive.\n\n"
        "Worst case feels prudent. It feels conservative and responsible. But "
        "think about what it is claiming. It says every one of your twenty-five "
        "inputs simultaneously sits at the far edge of its range, all in the "
        "same direction. Population overcounted at the maximum, body weight at "
        "the maximum, digestibility at the worst end, methane conversion at the "
        "top, all at once.\n\n"
        "If those things are roughly independent, that combination is "
        "astronomically unlikely. Reporting it as your uncertainty is not "
        "prudent, it is wrong, and it makes your inventory look far weaker than "
        "it is.\n\n"
        "The truth sits somewhere between one input's range and the sum of all "
        "of them. And here is the problem: you cannot guess where. That is what "
        "the rest of this session is about."
    ),
},

# ======================================== C. APPROACH 1 AND ITS LIMITS (4)
{
    "layout": "bullets",
    "kicker": "IPCC Vol. 1 Ch. 3",
    "title": "Approach 1: combine the ranges with a formula",
    "bullets": [
        ("For a product", "Activity data times an emission factor: add the squared relative uncertainties, then take the square root."),
        ("For a sum", "Adding source categories together: root-sum-of-squares, weighted by how big each source is."),
        ("Why everyone starts here", "It runs in a spreadsheet. No software, no simulation, no programming."),
    ],
    "notes": (
        "IPCC gives you two approaches. This is the first one, and it is where "
        "most inventories begin, for a very good reason: it is arithmetic you "
        "can do in Excel in an afternoon.\n\n"
        "Do not let anyone tell you Approach 1 is wrong. It is not wrong. It is "
        "an approximation that is very good under certain conditions, and we "
        "are about to look at exactly what those conditions are.\n\n"
        "Note for honesty: our tool does not implement Approach 1 at all. It is "
        "Approach 2 only. We are covering Approach 1 because you need to "
        "understand what you are choosing instead of, not because the tool "
        "offers it as an option."
    ),
},
{
    "layout": "quadrature",
    "title": "Uncertainties combine like the sides of a triangle",
    "caption": "Plus or minus 10% combined with plus or minus 20% gives plus or minus 22.4%, not 30%.",
    "notes": (
        "This is the picture to remember from this section. If you remember "
        "nothing else about Approach 1, remember the triangle.\n\n"
        "Two uncertainties, 10% and 20%. Draw them at right angles. The "
        "combined uncertainty is the hypotenuse: the square root of 100 plus "
        "400, which is the square root of 500, which is 22.4%.\n\n"
        "Not 30%. Adding them is wrong, and this shows you by how much.\n\n"
        "The intuition behind the right angle is worth saying out loud: the two "
        "uncertainties are independent, they do not know about each other, so "
        "they point in different directions. Most of the time one is high while "
        "the other is somewhere in the middle. They partly cancel.\n\n"
        "And notice something important about the shape. The big uncertainty "
        "dominates. Twenty on its own was 20, and adding a 10 only moved it to "
        "22.4. Hold on to that, because it comes back when we look at which "
        "parameters are worth collecting better data on."
    ),
},
{
    "layout": "bullets",
    "title": "Approach 1 needs four things to be true",
    "bullets": [
        ("Roughly normal", "Every input is symmetric around its central value, a plain bell curve."),
        ("Not too wide", "Uncertainties below about 30% of the mean."),
        ("Independent", "No input moves together with any other input."),
        ("Nearly linear", "The equations are simple products and sums."),
    ],
    "notes": (
        "These are not small print. They are the conditions under which the "
        "formula is a good approximation, and when they hold, Approach 1 gives "
        "you an answer close to the truth for almost no effort.\n\n"
        "Read each one out and let it sit for a second, because the next slide "
        "goes through them one at a time and shows that a Tier 2 cattle "
        "inventory fails all four.\n\n"
        "Not three of four. All four."
    ),
},
{
    "layout": "bullets",
    "kicker": "And a Tier 2 cattle inventory",
    "title": "breaks all four of them",
    "bullets": [
        ("Not normal", "Emission factors are commonly skewed. They cannot go below zero, and they have a long tail on the high side."),
        ("Too wide", "Many livestock emission factors carry uncertainties of 30 to 100%, well past where the formula holds."),
        ("Not independent", "Digestibility and the methane conversion factor move together. Body weight and mature weight move together."),
        ("Not linear", "Net energy uses body weight to the power 0.75, and the energy ratios are polynomials in digestibility."),
    ],
    "notes": (
        "Go through these one at a time. This slide is the argument for the "
        "whole tool, so do not rush it.\n\n"
        "Not normal. Think about a methane conversion factor. It cannot be "
        "negative. It has a floor at zero but no hard ceiling, so its "
        "distribution leans, with a longer tail upward than downward. A "
        "symmetric plus or minus cannot describe that.\n\n"
        "Too wide. The IPCC defaults for several nitrogen coefficients are in "
        "the tens of percent, and some run to a factor of two. The formula was "
        "never meant for that range.\n\n"
        "Not independent. This one is biology, not statistics. A herd on better "
        "feed has higher digestibility, and higher digestibility means a lower "
        "fraction of energy lost as methane. Those two parameters are linked by "
        "the animal. Assuming they are independent is assuming something "
        "untrue about cattle.\n\n"
        "Not linear. Maintenance energy scales with body weight to the power "
        "0.75. That is a curve, not a straight line. Put a symmetric range in "
        "and you do not get a symmetric range out.\n\n"
        "So: the one case Approach 1 is least suited to is the one you are "
        "actually doing."
    ),
},

# ==================================== D. THE MONTE CARLO IDEA (8 slides)
{
    "layout": "section",
    "kicker": "The core of the session",
    "title": "So stop using a formula.",
    "subtitle": "Try thousands of possible inventories instead, and look at how they spread out.",
    "notes": (
        "Pause here. This is the pivot of the whole afternoon.\n\n"
        "Every problem on the last slide came from trying to find a formula "
        "that combines ranges. Monte Carlo does not look for that formula. It "
        "sidesteps the question entirely.\n\n"
        "The idea is almost embarrassingly simple, and people often distrust it "
        "for that reason. Let it land before you move on."
    ),
},
{
    "layout": "step_figure",
    "step": "Step 1",
    "title": "Draw one value for every input",
    "image": "gifs/g1_one_draw.gif",
    "body": "Pick a value at random from each input's range, respecting its shape. Values near the centre come up more often than values at the edges.",
    "notes": (
        "This is what sampling from a distribution means, and that is all it "
        "means. You have a range and a shape, and you pick one value from it at "
        "random, in a way that respects the shape.\n\n"
        "Watch the animation for a few seconds and let people see the pattern. "
        "The marker lands near the middle most of the time and out at the edges "
        "only occasionally. That is the bell curve doing its job.\n\n"
        "Now do that for every uncertain input at once. One draw for "
        "population, one for body weight, one for digestibility, one for every "
        "coefficient. You now have one complete, plausible set of inputs. Not "
        "the best set, just a plausible one.\n\n"
        "If you want a physical image: it is rolling twenty-five differently "
        "weighted dice, once."
    ),
},
{
    "layout": "step_statement",
    "step": "Step 2",
    "title": "Run your inventory. Exactly as you already run it.",
    "body": [
        "The same IPCC Tier 2 equations. Equations 10.1 to 10.34.",
        "Nothing simplified. Nothing linearised. Nothing approximated.",
        "One complete inventory total comes out.",
    ],
    "notes": (
        "This is the step people skip past, and it is the one that makes the "
        "whole method work. Slow down here.\n\n"
        "There is no special uncertainty mathematics in this step. You take the "
        "twenty-five values you just drew, and you push them through exactly "
        "the same equation chain you already use in your Excel inventory. Net "
        "energy for maintenance, activity, growth, lactation. Gross energy. "
        "Enteric methane. Volatile solids. Nitrogen excretion. All of it, "
        "unchanged.\n\n"
        "One number comes out the other end. One possible value for your "
        "national total.\n\n"
        "That is why the method is exact where the formula is approximate. The "
        "formula has to make assumptions about the equations in order to work "
        "around them. Monte Carlo does not work around the equations, it just "
        "runs them."
    ),
},
{
    "layout": "step_statement",
    "step": "Step 3",
    "title": "Write the answer down. Then go back to Step 1.",
    "body": [
        "Draw. Calculate. Record.",
        "Then do it again, with a fresh set of draws.",
        "Ten thousand times.",
    ],
    "notes": (
        "Draw, calculate, record. Draw, calculate, record. Ten thousand times.\n\n"
        "Each pass is called an iteration, and that word will appear all over "
        "the tool. Ten thousand iterations means ten thousand alternative "
        "versions of your inventory, each one internally consistent, each one "
        "plausible given what you know about your inputs.\n\n"
        "Nobody does this by hand, obviously. The computer does it, and on the "
        "Country X example it takes a few seconds.\n\n"
        "And now the interesting part. You have ten thousand answers. What do "
        "you do with them?"
    ),
},
{
    "layout": "figure",
    "kicker": "One iteration",
    "title": "One answer tells you nothing",
    "image": "figures/f_build_n1.png",
    "caption": "n = 1",
    "notes": (
        "Here is iteration number one. A single tick on the axis.\n\n"
        "One inventory total, from one plausible set of inputs. On its own it "
        "is worthless: it tells you a number is possible and nothing about "
        "whether it is likely.\n\n"
        "Keep clicking."
    ),
},
{
    "layout": "figure",
    "kicker": "A hundred iterations",
    "title": "A hundred, and a shape starts to appear",
    "image": "figures/f_build_n100.png",
    "caption": "n = 100",
    "notes": (
        "A hundred iterations, and something is already visible. The answers "
        "are not spread evenly. They are bunching in the middle.\n\n"
        "That bunching is not an accident of the drawing. It is the same effect "
        "we saw on the triangle slide: for all twenty-five inputs to land at "
        "their extremes at once is very unlikely, so extreme totals are rare "
        "and middling totals are common.\n\n"
        "The edges are still ragged though. You would not want to quote a "
        "confidence interval off this."
    ),
},
{
    "layout": "figure",
    "kicker": "Two thousand iterations",
    "title": "Two thousand, and the shape is unmistakable",
    "image": "figures/f_build_n2000.png",
    "caption": "n = 2,000",
    "notes": (
        "Two thousand. The shape is now clear, and notice it is not quite "
        "symmetric. It leans, with a longer tail to the right.\n\n"
        "That lean is real and it came from the equations. We put mostly "
        "symmetric ranges in, and a skewed shape came out, because the Tier 2 "
        "chain is not linear. We will come back to that in a few slides, "
        "because it is the single best argument for this method.\n\n"
        "The edges are still moving between runs at this point. Not quite "
        "enough."
    ),
},
{
    "layout": "figure",
    "kicker": "Ten thousand iterations",
    "title": "Ten thousand. This is your answer.",
    "image": "figures/f6_histogram_final.png",
    "caption": "n = 10,000  ·  Country X  ·  seed 42  ·  AR5",
    "notes": (
        "Ten thousand iterations. The shape has stopped changing, and this is "
        "the answer to the question we started with.\n\n"
        "Not a number. A shape. And the shape carries more information than a "
        "number ever could: where the answer is likely to sit, how far it could "
        "reasonably stray, and which direction it is more likely to stray in.\n\n"
        "The dashed lines are the 95% confidence interval and we will build "
        "those on the next slide.\n\n"
        "Worth saying plainly at this point: no new mathematics was used "
        "anywhere in what we just did. We used your own inventory calculation, "
        "run many times, with the inputs jiggled. That is the whole method. "
        "That is precisely why it is exact where a formula is an approximation."
    ),
},
{
    "layout": "figure",
    "title": "Reading the pile: sort it, then cut the tails",
    "image": "gifs/g3_percentile_chop.gif",
    "caption": "Cut the lowest 250 and the highest 250. What remains is the middle 95%.",
    "notes": (
        "Getting the confidence interval out is easier than people expect. "
        "There is no formula here either.\n\n"
        "Sort all ten thousand answers from smallest to largest. Cut off the "
        "lowest 250, which is two and a half percent. Cut off the highest 250, "
        "which is another two and a half percent. What is left in the middle is "
        "95% of your simulated inventories.\n\n"
        "The value where you made the lower cut, and the value where you made "
        "the upper cut, are your 95% confidence interval.\n\n"
        "For Country X that is " + RUN["ci_lo"] + " to " + RUN["ci_hi"] +
        " tonnes, around a mean of " + RUN["mean"] + ".\n\n"
        "Then the margin of error is half the width of that interval, divided "
        "by the mean: " + RUN["moe"] + "%. That is the number that goes into "
        "Table 3.3.\n\n"
        "And read it in plain words, because this is how you will have to "
        "explain it: given the input uncertainties we stated, the true total is "
        "very likely to be somewhere inside that range."
    ),
},

# ============================= E. WHY THIS IS PROPAGATION (5 slides)
{
    "layout": "figure",
    "kicker": "The reason this is called propagation",
    "title": "The uncertainty travels through the equations, and changes shape",
    "image": "gifs/g4_propagation_chain.gif",
    "caption": "A symmetric input becomes a skewed output, because the equation chain is not a straight line.",
    "notes": (
        "This is the slide that answers the question in the session title: why "
        "does this propagate uncertainty, and why does propagating it properly "
        "matter.\n\n"
        "Watch the shape as it moves. A tidy symmetric range goes into the "
        "energy calculation. What comes out the other side is no longer "
        "symmetric, because body weight enters to the power 0.75 and that curve "
        "stretches one side more than the other. Push that through the methane "
        "step and it changes again.\n\n"
        "This is the thing a formula cannot do. Approach 1 takes a percentage "
        "in and gives a percentage out, and a percentage has no shape. It has "
        "no way of telling you that your upper tail is longer than your lower "
        "tail.\n\n"
        "And that difference is not academic. For Country X the interval is "
        "genuinely lopsided: " + RUN["lower_pct"] + "% below the mean and " +
        RUN["upper_pct"] + "% above it. If you are asked how badly you could be "
        "underestimating, those are different answers, and only Approach 2 can "
        "give you both.\n\n"
        "The tool reports the symmetric margin of error because that is what "
        "Table 3.3 asks for, but it keeps the asymmetric halves as well, and "
        "you will see them in the outputs tomorrow."
    ),
},
{
    "layout": "figure",
    "title": "Shape matters, so the tool asks you to choose one",
    "image": "figures/f3_distribution_gallery.png",
    "caption": "Every parameter row in the template carries a distribution. These are the shapes on offer.",
    "notes": (
        "When you fill in the template tomorrow, every parameter row has a "
        "distribution column, and this is what those names mean. Do not let the "
        "word distribution frighten anybody: it is just a description of which "
        "values are possible and how likely each one is.\n\n"
        "Normal is the plain symmetric bell curve. Use it when your estimate "
        "came from a survey and you have no reason to think it leans.\n\n"
        "Lognormal is skewed, with a long upper tail. Use it for emission "
        "factors, which cannot go below zero but can surprise you on the high "
        "side. Next slide has a warning about this one.\n\n"
        "Triangular and PERT are what you use when all you have is a minimum, a "
        "most likely and a maximum, which is exactly what expert judgement "
        "gives you. PERT is the gentler of the two: it puts less weight out at "
        "the corners.\n\n"
        "Beta is for anything bounded, like a fraction that has to stay between "
        "zero and one.\n\n"
        "Uniform says every value in the range is equally likely. That is a "
        "strong statement and usually an honest admission that you know very "
        "little.\n\n"
        "Constant means no uncertainty at all. Perfectly legitimate for "
        "something you know exactly.\n\n"
        "Practical advice: if you do not know, normal is a defensible default "
        "for activity data and animal performance, and the tool already "
        "pre-fills sensible choices for every IPCC coefficient."
    ),
},
{
    "layout": "bullets",
    "kicker": "One trap worth knowing before tomorrow",
    "title": "For a lognormal, the value you type is the median",
    "bullets": [
        ("What you type", "The tool reads your central value as the median of the distribution, not its arithmetic mean."),
        ("Why", "This follows the IPCC good practice guidance convention for skewed emission factor parameters."),
        ("What you will notice", "The simulated mean comes out above the value you entered, by roughly 10 to 25% for the asymmetric IPCC defaults."),
        ("Not a bug", "If you see that gap in your results, it is the convention working, not an error."),
    ],
    "notes": (
        "This is a small thing that causes real confusion, so it is worth two "
        "minutes now rather than a puzzled email in three months.\n\n"
        "For a skewed distribution the middle value and the average value are "
        "not the same thing. The long upper tail drags the average up above the "
        "middle. So when you type a central value for a lognormal parameter, "
        "the tool treats it as the middle, the median, and the average of the "
        "samples it draws will sit above it.\n\n"
        "For the IPCC asymmetric defaults the gap is somewhere between ten and "
        "twenty-five percent. If you go looking at the sampled values and the "
        "mean does not match what you typed, this is why.\n\n"
        "This is flagged in the User Guide as well, and it is one of the things "
        "we would like your view on: is it explained clearly enough?"
    ),
},
{
    "layout": "figure_bullets",
    "title": "Inputs that move together must be sampled together",
    "image": "figures/f7_correlation_scatter.png",
    "bullets": [
        ("The biology", "Better feed means higher digestibility and a lower share of energy lost as methane. The two move in opposite directions."),
        ("The consequence", "Drawing them independently invents herds that cannot exist, and usually makes you look more certain than you are."),
        ("What the tool does", "It draws each parameter from its own shape, then reorders the draws so the pairs move together correctly."),
        ("Why that matters", "The individual shapes you chose are preserved exactly. Adding correlation does not distort them."),
    ],
    "notes": (
        "Look at the two panels. On the left, digestibility and the methane "
        "conversion factor are drawn independently, and you get a shapeless "
        "cloud. On the right they are correlated, and the cloud tilts.\n\n"
        "The important thing to point at: the spread along each individual axis "
        "is identical in both panels. The method tilts the cloud without "
        "squashing it. That is deliberate, and it is the reason the tool uses "
        "this particular technique rather than an easier one.\n\n"
        "The name, if anyone asks, is Iman-Conover restricted pairing, and it "
        "works on rank correlations. You will not need to type that anywhere. "
        "What you will do tomorrow is tick a box on the correlations tab.\n\n"
        "The honest framing for why this matters: if you ignore correlation, "
        "you are assuming the animals in your herd do not have biology. The "
        "parameters are linked through the animal whether you model it or not."
    ),
},
{
    "layout": "figure_bullets",
    "title": "And an honest word about how much that changes",
    "image": "figures/f8_ci_width_compare.png",
    "bullets": [
        ("Country X, no correlations", "Margin of error " + RUN["moe"] + "%"),
        ("Country X, structural defaults", "Margin of error " + RUN["moe_corr"] + "%, about " + RUN["corr_widening"] + "% wider"),
        ("The central estimate", "Essentially unchanged. Correlation moves the width, not the middle."),
        ("Where the preset comes from", "Expert elicitation, documented in the methodology. IPCC publishes no numerical correlations for livestock parameters, so the tool does not claim it does."),
    ],
    "notes": (
        "Be straight with them about the size of this effect, because if you "
        "oversell it and they see an eight percent change they will distrust "
        "everything else you said.\n\n"
        "Turning on the full correlation preset widens the interval by about "
        "eight percent here. That is a real effect and worth having, but it is "
        "not dramatic, and a small effect is the correct result rather than a "
        "sign that something is broken.\n\n"
        "The last bullet matters for your credibility with reviewers. Those "
        "correlation values are expert judgement. They are documented, each "
        "pair has a stated rationale, and the tool calls them structural "
        "defaults precisely because IPCC has not published numbers for them. If "
        "anyone tells you these are IPCC values, they are wrong, and you should "
        "not repeat it.\n\n"
        "This is a good moment to ask whether they would want to substitute "
        "their own correlation judgements, and note the answer down for "
        "Deliverable 1."
    ),
},

# ======================== F. WHY APPROACH 2 IS BETTER (3 slides)
{
    "layout": "table",
    "title": "The two approaches, side by side",
    "headers": ["Your situation", "Approach 1", "Approach 2"],
    "rows": [
        ["Uncertainties under about 30%, symmetric", "adequate", "works too"],
        ["Large uncertainties, and many livestock EFs are 30 to 100%", "biased", "correct"],
        ["Skewed or bounded distributions", "cannot represent", "native"],
        ["Correlated inputs", "assumes independence", "handled"],
        ["Non-linear model, such as the Tier 2 energy chain", "linear approximation", "exact"],
        ["Key categories, under IPCC good practice", "minimum", "encouraged"],
    ],
    "notes": (
        "This table is on the project website and you can point your agency "
        "colleagues at it.\n\n"
        "Read down the first column and notice that the top row is the only one "
        "where Approach 1 is comfortable. Everything below it is a case where "
        "Approach 1 is either biased or simply unable to represent what is "
        "going on.\n\n"
        "The bottom row is the one to use in a meeting. IPCC good practice "
        "encourages Approach 2 for key categories, and in both your countries "
        "livestock is a key category. That is not a preference, that is the "
        "guidance pointing at the method.\n\n"
        "And the summary argument: a Tier 2 cattle inventory is exactly the "
        "case Approach 2 exists for. The chain is non-linear, several emission "
        "factors are wide and asymmetric, and biologically related parameters "
        "co-vary. All three at once."
    ),
},
{
    "layout": "figure",
    "title": "What that costs you, in one picture",
    "image": "figures/f4_approach1_vs_2.png",
    "caption": "The same inputs through a non-linear step: the formula's symmetric answer against the simulated truth.",
    "notes": (
        "This is the previous table reduced to one picture.\n\n"
        "Same inputs, same equation. The outline is what Approach 1 would "
        "report: symmetric, centred, tidy. The filled shape is what actually "
        "happens when you push the inputs through the equation.\n\n"
        "Two things to point at. The true shape leans, so a symmetric answer "
        "misstates both tails at once: too generous on one side, too tight on "
        "the other. And the peak has shifted relative to where the formula "
        "puts it.\n\n"
        "If somebody asks which direction the error goes, the honest answer is "
        "that it depends on the equation and you cannot know without running "
        "it. Which is itself the argument for running it."
    ),
},
{
    "layout": "figure_bullets",
    "kicker": "And you get this for free",
    "title": "Which input should you fix first?",
    "image": "figures/f5_tornado.png",
    "bullets": [
        ("Where it comes from", "You kept 10,000 paired records of inputs and outputs. So you can simply ask which input moved the answer most."),
        ("Country X says", "Feed digestibility, then population, then the methane conversion factor, then body weight."),
        ("Purple bars", "Parameters better local data could improve."),
        ("Faded bars", "Fixed IPCC coefficients. You are not going to change these."),
    ],
    "notes": (
        "This is where uncertainty analysis stops being a reporting obligation "
        "and starts being useful to you.\n\n"
        "Because you kept every input and its matching output, you can ask "
        "which input actually drove the variation. That is the ranking on the "
        "screen. For Country X, digestibility dominates, and four of the top "
        "five bars are parameters that better local data could improve.\n\n"
        "Now make the connection explicitly, because this is the moment the "
        "method should click for both of them.\n\n"
        "You have already done this. When the decision was made to survey the "
        "extensive system in both countries, that was a judgement about where "
        "the uncertainty was concentrated and where new data would buy the "
        "most. This chart is the formal version of that judgement. It does the "
        "arithmetic instead of relying on instinct, and it tells you where the "
        "next survey would narrow the interval most.\n\n"
        "That is a sentence worth taking to a funding conversation: this is "
        "where our reported uncertainty comes from, and this is what it would "
        "cost to reduce it."
    ),
},

# ============================ G. TRUSTING THE ANSWER (4 slides)
{
    "layout": "figure",
    "title": "How many iterations is enough?",
    "image": "gifs/g5_convergence.gif",
    "caption": "The margin of error settles as the iteration count grows. Early on it swings; by ten thousand it has stopped moving.",
    "notes": (
        "A fair question at this point: if the answers come from random "
        "draws, how do you know you have done enough of them?\n\n"
        "Watch the line. At a hundred iterations the estimated margin of error "
        "is swinging around wildly, because you are looking at the tails of a "
        "distribution and you have barely any values out there. By a few "
        "thousand it is calming down. By ten thousand it has essentially "
        "stopped moving.\n\n"
        "The practical guidance, and this is in the tool as well: ten thousand "
        "is the working minimum for anything you intend to use, and twenty-five "
        "to thirty thousand for a final reporting run. Use a thousand only for "
        "a quick test while you are setting things up.\n\n"
        "Higher is always better. The only cost is your time, and even thirty "
        "thousand on a normal inventory is minutes, not hours."
    ),
},
{
    "layout": "bullets",
    "title": "Run it twice. That is the check.",
    "bullets": [
        ("Two runs will differ slightly", "That is expected. Different random draws, slightly different answer. It is not a sign of a problem."),
        ("The seed", "A number that fixes the random draws. Same seed, same inputs, identical results. That is how you make a run reproducible for a reviewer."),
        ("The test", "Re-run with a different seed. If the margin of error moves by more than about two percentage points, use more iterations."),
        ("Report the seed", "Put it in your documentation. It lets anyone reproduce your exact numbers."),
    ],
    "notes": (
        "This is the single most practical quality check in the whole method, "
        "and it takes two minutes.\n\n"
        "Run it, note the margin of error, change the seed, run it again. If "
        "your margin of error was 24.4 and comes back 24.6, you are fine. If it "
        "comes back 29, you did not use enough iterations.\n\n"
        "Two percentage points is the rule of thumb the tool uses, and it is a "
        "reasonable one.\n\n"
        "On the seed: worth being clear that setting a seed does not make the "
        "result more correct, it makes it repeatable. A reviewer who has your "
        "template and your seed can reproduce your table exactly, which is a "
        "strong position to be in during a review.\n\n"
        "This is another item to ask them about: is the convergence guidance in "
        "the User Guide clear enough to act on?"
    ),
},
{
    "layout": "statement",
    "kicker": "One thing to clear up",
    "title": "This is not MCMC.",
    "body": [
        "No chains. No warm-up. No burn-in. No convergence diagnostics borrowed from Bayesian software.",
        "Every iteration here is drawn independently of every other one.",
        "If you have met Bayesian tools before, put that vocabulary aside.",
    ],
    "notes": (
        "Include this because someone in the room usually has met Bayesian "
        "software, or will be asked about it by a colleague who has, and the "
        "vocabulary gets mixed up constantly.\n\n"
        "Markov chain Monte Carlo is a different technique for a different "
        "problem. Its iterations depend on the previous one, which is why it "
        "needs burn-in and chain diagnostics.\n\n"
        "What we are doing is independent Monte Carlo. Every iteration is a "
        "fresh draw that knows nothing about the one before it. That is simpler "
        "and it is why the convergence check is just run it twice.\n\n"
        "The tool's own diagnostics panel says this explicitly, so you will see "
        "it again tomorrow."
    ),
},
{
    "layout": "statement",
    "kicker": "And the limit of the method",
    "title": "Monte Carlo propagates the ranges you give it.",
    "body": [
        "It does not check them. It does not know if they are right.",
        "A wrong input range produces a confidently wrong output range.",
        "Which is why tomorrow morning is about preparing input data.",
    ],
    "notes": (
        "End the concepts here, and end on honesty rather than on a sales "
        "pitch.\n\n"
        "Everything we have looked at this afternoon is machinery for carrying "
        "your input uncertainties through to your output uncertainty, "
        "faithfully. It is very good at that. It has no opinion whatsoever "
        "about whether your input uncertainties were sensible.\n\n"
        "If you tell it that body weight is known to plus or minus two percent "
        "when really it is plus or minus twenty, it will hand you a beautifully "
        "computed, precisely wrong confidence interval. And it will look just "
        "as convincing as a correct one.\n\n"
        "So the quality of this analysis rests on the work we did this morning: "
        "deciding what each range should be and being able to say where it came "
        "from. That is the real skill, and it is why tomorrow morning is a whole "
        "session on preparing input data.\n\n"
        "Now let us go and run it."
    ),
},

# ======================= H. GUIDED LIVE RUN (9 slides)
{
    "layout": "section",
    "kicker": "The rest of the session",
    "title": "Let us run it together.",
    "subtitle": "Country X, the built-in example. Nothing to upload, nobody blocked.",
    "notes": (
        "Everyone open the tool now. We are using the built-in Country X "
        "example, so nobody needs a file and nobody gets stuck at the first "
        "step.\n\n"
        "I will go slowly and stop at every point where something on screen "
        "matches something we just covered. Interrupt whenever you like: "
        "questions during this part are worth more than questions at the end.\n\n"
        "And please say when something is confusing, awkward or badly labelled. "
        "That is Deliverable 1, and the useful version of it is the reaction you "
        "have in the moment, not the one you reconstruct next week."
    ),
},
{
    "layout": "screenshot",
    "step": "1",
    "title": "Load the Country X example",
    "image": "screenshots/s1_load_example.png",
    "instruction": "Tab 1, Data Input. Choose 'Country X (hypothetical dairy)' from the dropdown.",
    "notes": (
        "Tab 1. Pick Country X from the dropdown and the parameters populate "
        "immediately.\n\n"
        "Point out that this is also how they should explore the tool at home: "
        "no data needed, nothing to prepare, no way to break anything.\n\n"
        "Country X is a hypothetical smallholder dairy system. It is not either "
        "of your countries and it is not meant to be. Deliberately so, because "
        "nobody should be defending their own numbers while they are learning "
        "the interface."
    ),
},
{
    "layout": "screenshot",
    "step": "2",
    "title": "Every row here is a distribution, not a number",
    "image": "screenshots/s2_parameters.png",
    "instruction": "Look at the columns: central value, lower, upper, distribution. That is Step 1 of the three steps.",
    "notes": (
        "Connect this straight back to Step 1 of the three steps.\n\n"
        "Each row is one uncertain input. It has a central value, a lower "
        "bound, an upper bound and a distribution shape. Those four things are "
        "exactly what the sampler needs in order to draw a value.\n\n"
        "Two things worth pointing at specifically.\n\n"
        "First: the bounds are read as the 95% interval, not as absolute "
        "minimum and maximum. So a value of 400 with bounds 360 and 440 means "
        "you believe there is a 95% chance the true value is in there, not that "
        "it is impossible to be outside. That trips people up.\n\n"
        "Second: scroll down to the advanced coefficients and show that they "
        "are all pre-filled from the IPCC catalogue. The user supplies the core "
        "herd data; the tool supplies the coefficients and their published "
        "ranges. Nobody has to go hunting in the guidelines for a default value "
        "for Bo."
    ),
},
{
    "layout": "screenshot",
    "step": "3",
    "title": "Tell it which inputs move together",
    "image": "screenshots/s3_correlations.png",
    "instruction": "Tab 4, Correlations. Use the structural defaults preset, or set your own.",
    "notes": (
        "This is the correlation slide made real.\n\n"
        "The preset applies the seven expert-elicited parameter pairs we "
        "discussed: digestibility with methane conversion, body weight with "
        "mature weight, milk yield with fat content and so on. Each one has a "
        "documented rationale in the methodology.\n\n"
        "Remind them of the honest framing: this widens the interval by about "
        "eight percent on this example, and these are expert judgements rather "
        "than IPCC-published values.\n\n"
        "Ask whether the labelling on this tab makes that distinction clear "
        "enough. This is exactly the sort of thing Deliverable 1 should cover."
    ),
},
{
    "layout": "screenshot",
    "step": "4",
    "title": "Set the iterations and the seed, then run",
    "image": "screenshots/s4_simulate.png",
    "instruction": "Tab 5, Simulate. Ten thousand iterations, seed 42, then run.",
    "notes": (
        "Two settings, both of which we covered.\n\n"
        "Iterations: ten thousand is the working minimum. The slider goes to "
        "fifty thousand. For a final reporting run, twenty-five to thirty "
        "thousand.\n\n"
        "Seed: forty-two is the default. Changing it is how you do the "
        "convergence check we talked about.\n\n"
        "Now click run, and while it is working, say what is happening: it is "
        "drawing ten thousand sets of values and pushing each one through the "
        "full equation chain. That is the three steps, ten thousand times.\n\n"
        "It takes a few seconds on this example. On a large multi-group "
        "national inventory it takes longer, and tomorrow we will see that on "
        "something more realistic."
    ),
},
{
    "layout": "screenshot",
    "step": "5",
    "title": "There it is. The same histogram, on your own screen.",
    "image": "screenshots/s5_histogram.png",
    "instruction": "This is the pile of 10,000 answers we built up slide by slide.",
    "notes": (
        "This is the payoff moment of the session. Let it land.\n\n"
        "That is the same picture we built up four slides at a time, except "
        "now it came out of their own machine, from their own click, thirty "
        "seconds ago.\n\n"
        "Point at the shape and ask them to describe it back to you. Where is "
        "it centred, is it symmetric, which tail is longer. Getting them to say "
        "it out loud is worth more than another explanation from you.\n\n"
        "The reading guide in the tool puts it simply: narrow and tall means "
        "low uncertainty, wide and flat means high uncertainty."
    ),
},
{
    "layout": "screenshot",
    "step": "6",
    "title": "The confidence interval and the margin of error",
    "image": "screenshots/s6_metrics.png",
    "instruction": "Mean, 95% interval, margin of error. The margin of error is what Table 3.3 wants.",
    "notes": (
        "These are the numbers that leave the tool and go into your inventory "
        "report.\n\n"
        "Mean " + RUN["mean"] + ". Interval " + RUN["ci_lo"] + " to " +
        RUN["ci_hi"] + ". Margin of error " + RUN["moe"] + " percent.\n\n"
        "If their numbers differ slightly from mine, that is the seed and it is "
        "a good accident: it demonstrates the run-it-twice point better than my "
        "slide did. If everyone used seed 42 they will match exactly, which "
        "demonstrates reproducibility instead. Either way there is a lesson on "
        "the screen.\n\n"
        "Point out the asymmetric halves if the panel shows them: " +
        RUN["lower_pct"] + "% below and " + RUN["upper_pct"] + "% above. Table "
        "3.3 takes the single symmetric figure, but the tool keeps both, and "
        "the difference is the non-linearity we saw earlier."
    ),
},
{
    "layout": "screenshot",
    "step": "7",
    "title": "Table 3.3, ready to report",
    "image": "screenshots/s7_table33.png",
    "instruction": "Activity data, emission factor, combined. Per source category, in the IPCC format.",
    "notes": (
        "This is the output your inventory agency actually needs, in the format "
        "the reporting table expects.\n\n"
        "Explain where the three columns come from, because it is neat and it "
        "reuses everything we covered. The tool runs the simulation three "
        "times: once with everything varying, once with the emission factors "
        "held at their central values, and once with the activity data held "
        "fixed. The spread from each run gives you one column.\n\n"
        "A convention worth flagging: in this tool, population is the only "
        "parameter classified as activity data. Everything else, including body "
        "weight and milk yield, counts as an emission factor input. That "
        "follows the IPCC split, and it surprises people, so say it clearly.\n\n"
        "Walter, this is the table that has to get into the IPCC software, so "
        "your view on whether this format transfers cleanly is particularly "
        "useful for Deliverable 1."
    ),
},
{
    "layout": "screenshot",
    "step": "8",
    "title": "The ranking, the checks, and the downloads",
    "image": "screenshots/s8_sensitivity.png",
    "instruction": "Tab 6 for the tornado. Then the diagnostics panel, then Excel, CSV and the Word report.",
    "notes": (
        "Three things to close the run on.\n\n"
        "The tornado, which is the slide about which parameter to fix first, "
        "now on their own data. Ask them whether the ranking matches their "
        "intuition about their own inventories. That conversation is worth "
        "having now while the picture is in front of them.\n\n"
        "The diagnostics panel, which is the automated version of the run it "
        "twice check. All three checks should be green before anything gets "
        "submitted.\n\n"
        "And the downloads. Excel and CSV for the numbers, and a Word report "
        "that writes up the run in prose, including which values were "
        "auto-filled rather than supplied. That report is a good starting point "
        "for the uncertainty section of an inventory report, and it is worth "
        "you both looking at whether it says enough."
    ),
},

# ================================== I. CLOSE (2 slides)
{
    "layout": "recap",
    "title": "That is the whole method",
    "steps": [
        ("Draw", "One value for every input, from its own range and shape."),
        ("Calculate", "Your own IPCC Tier 2 equations, unchanged, nothing approximated."),
        ("Record", "Keep the answer. Then do it again, ten thousand times."),
    ],
    "footer": "Then sort the answers, cut the outer 5%, and what remains is your confidence interval.",
    "notes": (
        "Three steps. That is genuinely all of it.\n\n"
        "Everything else we discussed, the distributions, the correlations, the "
        "iteration counts, the seeds, is detail around those three steps. If "
        "somebody in your ministry asks you what Monte Carlo is, this slide is "
        "your answer.\n\n"
        "And the sentence to go with it: no new mathematics was involved. We "
        "used your own inventory calculation, many times over, with the inputs "
        "varied across their plausible ranges. That is why the answer is exact "
        "where a formula would only approximate."
    ),
},
{
    "layout": "bullets",
    "kicker": "Before Session 4",
    "title": "What we would like you to look at",
    "bullets": [
        ("User Guide", "The sections on choosing a distribution, on correlations, and on convergence. Are they usable by someone who has not sat through this afternoon?"),
        ("Technical Methodology", "The Monte Carlo and uncertainty metrics sections. Is the method described well enough to defend to a reviewer?"),
        ("What to write down", "Anything unclear, anything missing, anything that assumed knowledge you do not have. Wrong wording counts."),
        ("Where it goes", "Deliverable 1: written feedback on the tool and its guidance, with recommendations."),
    ],
    "footer": "Tomorrow morning: preparing and translating your own input data.",
    "notes": (
        "Hand over to the document review that closes this session, or set it "
        "as homework if we are running late.\n\n"
        "Be explicit about what useful feedback looks like, because people are "
        "polite and will otherwise tell you it was fine. The most valuable "
        "thing either of you can report is the exact sentence where you got "
        "lost, and what you thought it meant before you worked it out.\n\n"
        "Say clearly that criticism of the documentation is the point of the "
        "exercise, not a side effect of it. You are the intended readers. If it "
        "does not work for you it does not work.\n\n"
        "Then flag tomorrow: Session 4 is preparing and translating input data, "
        "which is the answer to the limitation we ended the concepts on. Good "
        "ranges in, trustworthy interval out."
    ),
},
]

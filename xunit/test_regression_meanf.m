function test_suite = test_regression_meanf
initTestSuite;

% Set random number stream so that test failing isn't because randomness.
% Run demo & save test values.

function testDemo
stream0 = RandStream('mt19937ar','Seed',0);
if str2double(regexprep(version('-release'), '[a-c]', '')) < 2012
  prevstream = RandStream.setDefaultStream(stream0);
else
  prevstream = RandStream.setGlobalStream(stream0);
end
disp('Running: demo_regression_meanf')
demo_regression_meanf
path = which('test_regression_meanf.m');
path = strrep(path,'test_regression_meanf.m', 'testValues');
if ~(exist(path, 'dir') == 7)
    mkdir(path)
end
path = strcat(path, '/testRegression_meanf'); 
save(path, 'Eft');
if str2double(regexprep(version('-release'), '[a-c]', '')) < 2012
  RandStream.setDefaultStream(stream);
else
  RandStream.setGlobalStream(stream);
end
RandStream.setDefaultStream(stream);
drawnow;clear;close all


function testPredictions
values.real = load('realValuesRegression_meanf.mat', 'Eft');
values.test = load(strrep(which('test_regression_meanf.m'), 'test_regression_meanf.m', 'testValues/testRegression_meanf.mat'), 'Eft');
assertElementsAlmostEqual(mean(values.real.Eft), mean(values.test.Eft), 'relative', 0.10);


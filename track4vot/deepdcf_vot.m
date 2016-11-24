function deepdcf_vot

% *************************************************************
% VOT: Always call exit command at the end to terminate Matlab!
% *************************************************************
% cleanup = onCleanup(@() exit() );

% *************************************************************
% VOT: Set random seed to a different value every time.
% *************************************************************
% RandStream.setGlobalStream(RandStream('mt19937ar', 'Seed', sum(clock)));

% **********************************
% VOT: Get initialization data
% **********************************
[handle, image, region] = vot('rectangle');

vl_setupnn();
% Initialize the tracker
[state, ~] = deepdcf_initialize(imread(image), region);

while true
    
    % **********************************
    % VOT: Get next frame
    % **********************************
    [handle, image] = handle.frame(handle);
    
    if isempty(image)
        break;
    end;
    
    % Perform a tracking step, obtain new region
    [state, region] = deepdcf_update(state, imread(image));
    
    % **********************************
    % VOT: Report position for frame
    % **********************************
    handle = handle.report(handle, region);
    
end;

% **********************************
% VOT: Output the results
% **********************************
handle.quit(handle);

end

function [state, location] = deepdcf_initialize(I, region, varargin)

net = load('simplenn_vgg_deepdcfnet.mat');
state.net = vl_simplenn_tidy(net.net) ;


state.lambda = 1e-4;
state.padding = 1.5;
state.output_sigma_factor = 0.1; 
state.interp_factor = 0.02;
state.output_sigma = sqrt(prod([50,50]))*state.output_sigma_factor;

state.yf = fft2(gaussian_shaped_labels(state.output_sigma, state.net.meta.normalization.imageSize(1:2)));

state.pos = floor(region([2,1])+region([4,3])/2);
state.target_sz = region([4,3]);
state.window_sz = floor(state.target_sz*(1+state.padding));

patch = get_subwindow(I, state.pos, state.window_sz);

target = bsxfun(@minus,...
    single(imresize(patch,state.net.meta.normalization.imageSize(1:2))),...
    state.net.meta.normalization.averageImage);
res = vl_simplenn(state.net, target,[],[],'mode','test','conserveMemory',true);
xf = fft2(res(end).x);

kf = linear_correlation(xf, xf);
state.model_alphaf = state.yf ./ (kf + state.lambda);
state.model_xf = xf;

location = region;
imshow(uint8(I));
rectangle('Position',location);

end

function [state, location] = deepdcf_update(state, I, varargin)

patch = get_subwindow(I, state.pos, state.window_sz);

search = bsxfun(@minus,...
    single(imresize(patch,state.net.meta.normalization.imageSize(1:2))),...
    state.net.meta.normalization.averageImage);
res = vl_simplenn(state.net, search,[],[],'mode','test','conserveMemory',true);
zf = fft2(res(end).x);

kzf = linear_correlation(zf, state.model_xf);

response = real(ifft2(state.model_alphaf .* kzf));
[vert_delta, horiz_delta] = find(response == max(response(:)), 1);
if vert_delta > size(zf,1) / 2,  %wrap around to negative half-space of vertical axis
    vert_delta = vert_delta - size(zf,1);
end
if horiz_delta > size(zf,2) / 2,  %same for horizontal axis
    horiz_delta = horiz_delta - size(zf,2);
end
state.pos = state.pos + [vert_delta - 1, horiz_delta - 1].*...
    state.window_sz./state.net.meta.normalization.imageSize(1:2);

patch = get_subwindow(I, state.pos, state.window_sz);
target = bsxfun(@minus,...
    single(imresize(patch,state.net.meta.normalization.imageSize(1:2))),...
    state.net.meta.normalization.averageImage);

res = vl_simplenn(state.net, target,[],[],'mode','test','conserveMemory',true);
xf = fft2(res(end).x);
kf = linear_correlation(xf, xf);
alphaf = state.yf ./ (kf + state.lambda);   %equation for fast training

state.model_alphaf = (1 - state.interp_factor) * state.model_alphaf + state.interp_factor * alphaf;
state.model_xf = (1 - state.interp_factor) * state.model_xf + state.interp_factor * xf;

box = [state.pos([2,1]) - state.target_sz([2,1])/2, state.target_sz([2,1])];

location = double(box);
imshow(uint8(I));
rectangle('Position',location);
drawnow

end










